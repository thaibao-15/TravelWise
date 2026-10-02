from fastapi.testclient import TestClient
from sqlmodel import SQLModel, Session, create_engine
from sqlmodel.pool import StaticPool

from app.main import app
from app.db.session import get_session


def run_tests():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    def get_session_override():
        with Session(engine) as session:
            yield session

    app.dependency_overrides[get_session] = get_session_override
    client = TestClient(app)

    print("1. Testing Register (POST /api/v1/auth/register)...")
    reg_payload = {
        "email": "test@gmail.com",
        "password": "123456",
        "full_name": "Test User",
    }
    response = client.post("/api/v1/auth/register", json=reg_payload)
    assert response.status_code == 201, f"Expected 201, got {response.status_code}: {response.text}"
    user_data = response.json()
    assert user_data["email"] == "test@gmail.com"
    assert user_data["full_name"] == "Test User"
    assert "password" not in user_data
    assert user_data["role"] == "USER"
    assert user_data["is_active"] is True
    print("   -> Register SUCCESS:", user_data)

    print("2. Testing Duplicate Register (HTTP 409)...")
    response_dup = client.post("/api/v1/auth/register", json=reg_payload)
    assert response_dup.status_code == 409, f"Expected 409, got {response_dup.status_code}"
    print("   -> Duplicate register correctly returned 409 Conflict")

    print("3. Testing Login wrong password (HTTP 401)...")
    response_wrong = client.post(
        "/api/v1/auth/login",
        json={"email": "test@gmail.com", "password": "wrongpassword"},
    )
    assert response_wrong.status_code == 401, f"Expected 401, got {response_wrong.status_code}"
    print("   -> Wrong password correctly returned 401 Unauthorized")

    print("4. Testing Login correct password (HTTP 200)...")
    response_login = client.post(
        "/api/v1/auth/login",
        json={"email": "test@gmail.com", "password": "123456"},
    )
    assert response_login.status_code == 200, f"Expected 200, got {response_login.status_code}"
    token_data = response_login.json()
    assert "access_token" in token_data
    assert token_data["token_type"] == "bearer"
    access_token = token_data["access_token"]
    print("   -> Login SUCCESS. Received token:", access_token[:20] + "...")

    print("5. Testing GET /api/v1/auth/me without token (HTTP 401)...")
    response_no_token = client.get("/api/v1/auth/me")
    assert response_no_token.status_code == 401, f"Expected 401, got {response_no_token.status_code}"
    print("   -> No token correctly returned 401 Unauthorized")

    print("6. Testing GET /api/v1/auth/me with valid Bearer token (HTTP 200)...")
    headers = {"Authorization": f"Bearer {access_token}"}
    response_me = client.get("/api/v1/auth/me", headers=headers)
    assert response_me.status_code == 200, f"Expected 200, got {response_me.status_code}"
    me_data = response_me.json()
    assert me_data["email"] == "test@gmail.com"
    assert me_data["full_name"] == "Test User"
    assert "password" not in me_data
    print("   -> GET /me SUCCESS:", me_data)

    print("\n>>> ALL AUTHENTICATION TESTS PASSED PERFECTLY! <<<")


if __name__ == "__main__":
    run_tests()
