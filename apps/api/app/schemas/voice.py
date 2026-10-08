from typing import Optional

from pydantic import BaseModel, Field


class TTSRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=5000, description="Nội dung cần đọc")
    language: str = Field("vi", description="Ngôn ngữ đọc (mặc định 'vi')")
    speaker_id: Optional[str] = Field("HN-Nam-1-BL", description="Giọng đọc")
    model: str = Field("v2.0_pro", description="Mô hình Blaze AI")
    audio_speed: str = Field("1", description="Tốc độ đọc (ví dụ: '1', '1.1')")
    audio_quality: int = Field(64, description="Chất lượng audio (ví dụ: 64)")
    audio_format: str = Field("wav", description="Định dạng audio (ví dụ: 'wav', 'mp3')")
    normalization: str = Field("basic", description="Chế độ chuẩn hóa")


class TTSCreateResponse(BaseModel):
    id: str = Field(..., description="TTS ID")


class TTSInfoResponse(BaseModel):
    id: str
    status: str
    audio_format: str
    audio_quality: int
    speaker_id: str
