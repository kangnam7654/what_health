from pydantic import BaseModel


class AppleAuthRequest(BaseModel):
    identity_token: str
    authorization_code: str | None = None
    full_name: str | None = None
    email: str | None = None


class GoogleAuthRequest(BaseModel):
    authorization_code: str
    redirect_uri: str = "urn:ietf:wg:oauth:2.0:oob"


class AuthUserInfo(BaseModel):
    id: str
    email: str | None = None
    display_name: str | None = None
    subscription_tier: str = "free"


class AuthResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: AuthUserInfo


class RefreshTokenRequest(BaseModel):
    refresh_token: str
