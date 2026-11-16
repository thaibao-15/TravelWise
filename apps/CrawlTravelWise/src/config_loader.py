from __future__ import annotations

import sys
from pathlib import Path
from typing import List, Literal
from pydantic import BaseModel, Field, field_validator

# Sử dụng tomllib built-in (Python 3.11+) hoặc fallback tomli
if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib


class TargetConfig(BaseModel):
    hl: str = Field(default="vi", description="Mã ngôn ngữ giao diện Google Maps")
    gl: str = Field(default="VN", description="Mã quốc gia địa lý")
    center_lat: float = Field(default=16.0544, description="Vĩ độ trung tâm Đà Nẵng")
    center_lng: float = Field(default=108.2022, description="Kinh độ trung tâm Đà Nẵng")
    zoom_level: int = Field(default=14, ge=5, le=21, description="Độ zoom bản đồ")
    keywords: List[str] = Field(
        default_factory=lambda: ["quán cà phê Hải Châu Đà Nẵng"],
        description="Danh sách từ khóa cần tìm kiếm"
    )

    @field_validator("keywords")
    @classmethod
    def validate_keywords(cls, v: List[str]) -> List[str]:
        if not v:
            raise ValueError("Danh sách keywords không được để trống!")
        return [k.strip() for k in v if k.strip()]


class ScraperConfig(BaseModel):
    headless: bool = Field(default=False)
    browser_type: Literal["chromium", "firefox", "webkit"] = "chromium"
    max_results: int = Field(default=30, gt=0, le=500)
    navigation_timeout: int = Field(default=45000, description="ms")
    action_timeout: int = Field(default=10000, description="ms")
    min_delay: float = Field(default=1.5, ge=0.1)
    max_delay: float = Field(default=3.5, ge=0.5)
    concurrency: int = Field(default=2, ge=1, le=10)
    user_agent: str = Field(
        default="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    )

    @field_validator("max_delay")
    @classmethod
    def validate_delay(cls, v: float, info) -> float:
        min_d = info.data.get("min_delay", 1.0)
        if v < min_d:
            raise ValueError(f"max_delay ({v}) phải lớn hơn hoặc bằng min_delay ({min_d})")
        return v


class StorageConfig(BaseModel):
    output_dir: Path = Field(default=Path("output"))
    format: Literal["json", "jsonl"] = "jsonl"
    write_mode: Literal["append", "overwrite"] = "append"
    output_filename: str = Field(default="danang_places.jsonl")

    @field_validator("output_dir", mode="before")
    @classmethod
    def convert_path(cls, v: str | Path) -> Path:
        return Path(v)


class AppConfig(BaseModel):
    target: TargetConfig
    scraper: ScraperConfig
    storage: StorageConfig


def load_config(config_path: str | Path = "config.toml") -> AppConfig:
    """Đọc file config.toml và validate qua Pydantic schema."""
    path = Path(config_path)
    if not path.is_file():
        raise FileNotFoundError(f"Không tìm thấy file cấu hình tại: {path.resolve()}")

    with open(path, "rb") as f:
        data = tomllib.load(f)

    return AppConfig.model_validate(data)

