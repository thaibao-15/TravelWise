from datetime import datetime, timedelta, timezone
from typing import Any, Optional
import jwt
from pwdlib import PasswordHash
from pwdlib.hashers.bcrypt import BcryptHasher

from app.core.config import settings

# Configure PasswordHash using BcryptHasher
password_hash = PasswordHash((BcryptHasher(),))


def hash_password(password: str) -> str:
    """Hash password using BCrypt."""
    return password_hash.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify plain password against BCrypt hash."""
    return password_hash.verify(plain_password, hashed_password)


def create_access_token(
    subject: str | int,
    email: str,
    role: str,
    expires_delta: Optional[timedelta] = None,
) -> str:
    """Create JWT Access Token with sub, email, role, and exp."""
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(
            minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
        )

    to_encode: dict[str, Any] = {
        "sub": str(subject),
        "email": email,
        "role": role,
        "exp": expire,
    }

    encoded_jwt = jwt.encode(
        to_encode,
        settings.JWT_SECRET,
        algorithm=settings.JWT_ALGORITHM,
    )
    return encoded_jwt
