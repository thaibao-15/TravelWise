# pyrefly: ignore [missing-import]
import pytest
from unittest.mock import AsyncMock, patch
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

@pytest.fixture
def mock_httpx_client():
    with patch("httpx.AsyncClient") as mock_client:
        instance = mock_client.return_value
        instance.is_closed = False
        yield instance

@pytest.mark.asyncio
async def test_create_tts(mock_httpx_client):
    mock_post = AsyncMock()
    mock_post.return_value.status_code = 200
    mock_post.return_value.json.return_value = {"id": "12345-abc"}
    
    mock_httpx_client.post = mock_post
    
    response = client.post("/api/v1/voice/tts", json={
        "text": "Xin chào",
        "language": "vi",
        "speaker_id": "HN-Nam-1-BL",
        "model": "v2.0_pro",
        "audio_speed": "1",
        "audio_quality": 64,
        "audio_format": "wav",
        "normalization": "basic"
    })
    
    assert response.status_code == 200
    assert response.json() == {"id": "12345-abc"}

@pytest.mark.asyncio
async def test_get_tts_info(mock_httpx_client):
    mock_get = AsyncMock()
    mock_get.return_value.status_code = 200
    mock_get.return_value.json.return_value = {
        "id": "12345-abc",
        "status": "completed",
        "audio_format": "wav",
        "audio_quality": 64,
        "speaker_id": "HN-Nam-1-BL"
    }
    
    mock_httpx_client.get = mock_get
    
    response = client.get("/api/v1/voice/tts/12345-abc")
    
    assert response.status_code == 200
    assert response.json()["id"] == "12345-abc"
    assert response.json()["status"] == "completed"

@pytest.mark.asyncio
async def test_get_tts_options(mock_httpx_client):
    mock_get = AsyncMock()
    mock_get.return_value.status_code = 200
    mock_get.return_value.json.return_value = {
        "speakers": ["HN-Nam-1-BL"]
    }
    
    mock_httpx_client.get = mock_get
    
    response = client.get("/api/v1/voice/options")
    
    assert response.status_code == 200
    assert "speakers" in response.json()
