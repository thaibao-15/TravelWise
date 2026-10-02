from fastapi import HTTPException, status
from sqlmodel import Session, select

from app.core.security import create_access_token, hash_password, verify_password
from app.models.user import User
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse


class AuthService:
    @staticmethod
    def register_user(session: Session, register_data: RegisterRequest) -> User:
        statement = select(User).where(User.email == register_data.email)
        existing_user = session.exec(statement).first()
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email already registered",
            )

        hashed_password = hash_password(register_data.password)

        user = User(
            email=register_data.email,
            password=hashed_password,
            full_name=register_data.full_name,
            role="USER",
            is_active=True,
        )

        session.add(user)
        session.commit()
        session.refresh(user)
        return user

    @staticmethod
    def authenticate_user(session: Session, login_data: LoginRequest) -> User:
        statement = select(User).where(User.email == login_data.email)
        user = session.exec(statement).first()
        if not user or not user.password:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect email or password",
                headers={"WWW-Authenticate": "Bearer"},
            )

        if not verify_password(login_data.password, user.password):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect email or password",
                headers={"WWW-Authenticate": "Bearer"},
            )

        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="User account is disabled",
            )

        return user

    @staticmethod
    def create_user_token(user: User) -> TokenResponse:
        if user.id is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="User ID is missing",
            )
        access_token = create_access_token(
            subject=user.id,
            email=user.email,
            role=user.role,
        )
        return TokenResponse(access_token=access_token, token_type="bearer")
