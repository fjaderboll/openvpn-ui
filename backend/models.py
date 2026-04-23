from pydantic import BaseModel, field_validator
from typing import Optional
import re


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    token: str


class ClientCreate(BaseModel):
    name: str

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        if not re.match(r"^[a-zA-Z0-9_-]{1,32}$", v):
            raise ValueError(
                "Client name must be 1-32 characters, alphanumeric, hyphens, or underscores only"
            )
        if v.lower() == "server":
            raise ValueError("'server' is a reserved name")
        return v


class ClientInfo(BaseModel):
    name: str
    ip: str
    connected: bool
    real_address: Optional[str] = None
    virtual_address: Optional[str] = None
    bytes_received: Optional[int] = None
    bytes_sent: Optional[int] = None
    connected_since: Optional[str] = None
