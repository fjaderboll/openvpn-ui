import os
import hmac
import time
import secrets

import jwt
from fastapi import APIRouter, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from backend.models import LoginRequest, TokenResponse

router = APIRouter()
security = HTTPBearer()

SECRET_KEY = secrets.token_hex(32)

ADMIN_USERNAME = os.environ.get("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "changeme")


def create_token(username: str) -> str:
    payload = {
        "sub": username,
        "exp": int(time.time()) + 86400,  # 24 hours
    }
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")


def verify_token(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> str:
    try:
        payload = jwt.decode(
            credentials.credentials, SECRET_KEY, algorithms=["HS256"]
        )
        return payload["sub"]
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


@router.post("/login", response_model=TokenResponse)
async def login(request: LoginRequest):
    if not ADMIN_PASSWORD:
        raise HTTPException(
            status_code=500, detail="ADMIN_PASSWORD not configured"
        )
    username_match = hmac.compare_digest(request.username, ADMIN_USERNAME)
    password_match = hmac.compare_digest(request.password, ADMIN_PASSWORD)
    if username_match and password_match:
        token = create_token(request.username)
        return TokenResponse(token=token)
    raise HTTPException(status_code=401, detail="Invalid credentials")
