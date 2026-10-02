from fastapi import Depends, HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import jwt
from sqlmodel import Session

from app.core.config import settings
from app.db.session import get_session
from app.models.user import User

# HTTPBearer reads "Authorization: Bearer <token>" header.
# Unlike OAuth2PasswordBearer, it does NOT create a Swagger OAuth2 Password form.
# Swagger will display a simple "Value" text field for pasting the JWT directly.
http_bearer = HTTPBearer(auto_error=True)


def get_current_user(
    session: Session = Depends(get_session),
    credentials: HTTPAuthorizationCredentials = Security(http_bearer),
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    token = credentials.credentials
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET,
            algorithms=[settings.JWT_ALGORITHM],
        )
        user_id_str: str | None = payload.get("sub")
        if user_id_str is None:
            raise credentials_exception
        user_id = int(user_id_str)
    except (jwt.PyJWTError, ValueError):
        raise credentials_exception

    user = session.get(User, user_id)
    if not user:
        raise credentials_exception

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is disabled",
        )

    return user


__all__ = ["get_session", "get_current_user", "http_bearer"]
