mod auth;
mod config;
mod db;
mod error;
mod llm;
mod models;
mod quota;
mod subscription;

use axum::extract::Extension;
use axum::routing::{get, post};
use axum::Router;
use tower_http::cors::{Any, CorsLayer};

use crate::config::Config;

#[tokio::main]
async fn main() {
    // Load .env
    let _ = dotenvy::dotenv();

    // Logging
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info".into()),
        )
        .init();

    let config = Config::from_env();
    tracing::info!("Starting up: creating database tables");

    let pool = db::create_pool(&config.database_url)
        .await
        .expect("Failed to create database pool");

    tracing::info!("Database tables ready");

    // CORS
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    // Routes
    let auth_routes = Router::new()
        .route("/apple", post(auth::routes::apple_sign_in))
        .route("/google", post(auth::routes::google_sign_in))
        .route("/chatgpt/connect", post(auth::routes::chatgpt_connect))
        .route("/google/connect", post(auth::routes::google_connect))
        .route("/refresh", post(auth::routes::refresh_token))
        .route("/dev-login", post(auth::routes::dev_login))
        .route("/me", get(auth::routes::get_me))
        .route("/google/login", get(auth::routes::google_login_redirect))
        .route("/google/callback", get(auth::routes::google_callback));

    let api_routes = Router::new()
        .route("/chat", post(llm::routes::chat))
        .route("/generate-plan", post(llm::routes::generate_plan))
        .route("/models", get(llm::routes::get_models))
        .route("/quota", get(quota::routes::get_quota))
        .route("/quota/reward", post(quota::routes::claim_reward_ad))
        .route("/verify-receipt", post(subscription::routes::verify_receipt))
        .route(
            "/subscription",
            get(subscription::routes::get_subscription),
        );

    let app = Router::new()
        .route("/health", get(health_check))
        .nest("/auth", auth_routes)
        .nest("/api", api_routes)
        .layer(cors)
        .layer(Extension(pool))
        .layer(Extension(config));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080")
        .await
        .expect("Failed to bind to port 8080");

    tracing::info!("Server listening on 0.0.0.0:8080");

    axum::serve(listener, app)
        .await
        .expect("Server error");
}

async fn health_check() -> axum::Json<serde_json::Value> {
    axum::Json(serde_json::json!({"status": "ok"}))
}
