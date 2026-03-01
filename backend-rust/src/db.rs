use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;
use std::str::FromStr;

pub async fn create_pool(database_url: &str) -> Result<SqlitePool, sqlx::Error> {
    let opts = SqliteConnectOptions::from_str(database_url)?
        .create_if_missing(true)
        .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal);

    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(opts)
        .await?;

    create_tables(&pool).await?;
    Ok(pool)
}

async fn create_tables(pool: &SqlitePool) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            apple_user_id TEXT UNIQUE,
            google_user_id TEXT UNIQUE,
            openai_user_id TEXT UNIQUE,
            email TEXT UNIQUE,
            google_refresh_token TEXT,
            openai_access_token TEXT,
            openai_refresh_token TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS subscriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
            tier TEXT NOT NULL DEFAULT 'free',
            expires_at TEXT,
            product_id TEXT,
            transaction_id TEXT
        )
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS usage_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            date TEXT NOT NULL,
            request_count INTEGER NOT NULL DEFAULT 0,
            bonus_count INTEGER NOT NULL DEFAULT 0,
            reward_ads_watched INTEGER NOT NULL DEFAULT 0,
            UNIQUE(user_id, date)
        )
        "#,
    )
    .execute(pool)
    .await?;

    Ok(())
}
