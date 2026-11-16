from __future__ import annotations

import json
import logging
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Set
from pydantic import BaseModel, Field

from src.config_loader import StorageConfig

logger = logging.getLogger("DataPipeline")


class PlaceRecord(BaseModel):
    """Schema chuẩn hóa cho bản ghi địa điểm Đà Nẵng."""
    cid: Optional[str] = None
    name: str
    category: Optional[str] = None
    rating: Optional[float] = None
    review_count: Optional[int] = None
    raw_address: Optional[str] = None
    normalized_address: Optional[str] = None
    ward: Optional[str] = Field(None, description="Phường / Xã")
    district: Optional[str] = Field(None, description="Quận / Huyện tại Đà Nẵng")
    city: str = "Đà Nẵng"
    phone: Optional[str] = None
    website: Optional[str] = None
    opening_hours: Optional[str] = None
    price_level: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    google_maps_url: str
    search_keyword: str
    scraped_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


class DataPipeline:
    """
    Pipeline làm sạch dữ liệu, chuẩn hóa địa chỉ hành chính Đà Nẵng,
    và khử trùng lặp dựa trên CID hoặc URL.
    """

    DANANG_DISTRICTS = [
        "Hải Châu", "Sơn Trà", "Ngũ Hành Sơn",
        "Thanh Khê", "Liên Chiểu", "Cẩm Lệ",
        "Hòa Vang", "Hoàng Sa"
    ]

    def __init__(self, storage_cfg: StorageConfig):
        self.config = storage_cfg
        self.seen_identifiers: Set[str] = set()
        self.output_file: Path = self.config.output_dir / self.config.output_filename

        self._init_storage()

    def _init_storage(self) -> None:
        """Tạo thư mục output và load các CID đã tồn tại nếu chạy ở chế độ append."""
        self.config.output_dir.mkdir(parents=True, exist_ok=True)

        if self.config.write_mode == "overwrite" and self.output_file.exists():
            self.output_file.unlink()
            logger.info(f"Đã dọn dẹp file cũ: {self.output_file} (chế độ overwrite)")
        elif self.config.write_mode == "append" and self.output_file.exists():
            # Load existing records to deduplicate
            try:
                with open(self.output_file, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            record = json.loads(line)
                            cid = record.get("cid")
                            url = record.get("google_maps_url")
                            if cid:
                                self.seen_identifiers.add(str(cid))
                            elif url:
                                self.seen_identifiers.add(url)
                        except Exception:
                            continue
                logger.info(f"Đã tải {len(self.seen_identifiers)} định danh cũ từ {self.output_file} để khử trùng.")
            except Exception as e:
                logger.warning(f"Không thể đọc file cũ để load CID: {e}")

    def normalize_address(self, raw_addr: str) -> Dict[str, Optional[str]]:
        """
        Chuẩn hóa chuỗi địa chỉ, trích xuất Quận/Huyện và Phường nếu thuộc Đà Nẵng.
        """
        if not raw_addr:
            return {"normalized": None, "district": None, "ward": None}

        cleaned = re.sub(r"\s+", " ", raw_addr).strip()
        cleaned = re.sub(r",\s*Việt Nam$", "", cleaned, flags=re.IGNORECASE)

        district: Optional[str] = None
        for d in self.DANANG_DISTRICTS:
            if re.search(r"\b" + re.escape(d) + r"\b", cleaned, re.IGNORECASE):
                district = d
                break

        # Tìm Phường / Xã
        ward: Optional[str] = None
        ward_match = re.search(r"(?:Phường|P\.)\s+([A-Za-zÀ-ỹ0-9\s]+?)(?:,|$)", cleaned, re.IGNORECASE)
        if ward_match:
            ward = ward_match.group(1).strip()

        return {
            "normalized": cleaned,
            "district": district,
            "ward": ward
        }

    def process_item(self, raw_data: Dict[str, Any], search_keyword: str) -> Optional[PlaceRecord]:
        """
        Validate, khử trùng lặp và làm sạch một bản ghi.
        """
        name = raw_data.get("name", "").strip()
        if not name:
            return None

        cid = raw_data.get("cid")
        url = raw_data.get("google_maps_url", "")

        identifier = str(cid) if cid else url
        if not identifier or identifier in self.seen_identifiers:
            logger.debug(f"Bỏ qua bản ghi trùng lặp: {name} (ID: {identifier})")
            return None

        # Trích xuất và chuẩn hóa địa chỉ
        raw_addr = raw_data.get("address", "")
        addr_info = self.normalize_address(raw_addr)

        # Chuẩn hóa số điện thoại
        phone = raw_data.get("phone", "")
        if phone:
            phone = re.sub(r"[^\d+]", "", phone)

        record = PlaceRecord(
            cid=str(cid) if cid else None,
            name=name,
            category=raw_data.get("category") or None,
            rating=raw_data.get("rating"),
            review_count=raw_data.get("review_count"),
            raw_address=raw_addr or None,
            normalized_address=addr_info["normalized"],
            ward=addr_info["ward"],
            district=addr_info["district"],
            city="Đà Nẵng",
            phone=phone or None,
            website=raw_data.get("website") or None,
            opening_hours=raw_data.get("opening_hours") or None,
            price_level=raw_data.get("price_level") or None,
            latitude=raw_data.get("latitude"),
            longitude=raw_data.get("longitude"),
            google_maps_url=url,
            search_keyword=search_keyword,
        )

        self.seen_identifiers.add(identifier)
        return record

    def save_record(self, record: PlaceRecord) -> None:
        """Ghi trực tiếp bản ghi vào file JSONL hoặc tích lũy."""
        if self.config.format == "jsonl":
            with open(self.output_file, "a", encoding="utf-8") as f:
                f.write(record.model_dump_json(exclude_none=False) + "\n")
        else:
            # Đối với json thông thường, đọc - ghi (phù hợp dataset vừa phải)
            current_records = []
            if self.output_file.exists():
                try:
                    with open(self.output_file, "r", encoding="utf-8") as f:
                        current_records = json.load(f)
                except Exception:
                    current_records = []
            current_records.append(record.model_dump())
            with open(self.output_file, "w", encoding="utf-8") as f:
                json.dump(current_records, f, ensure_ascii=False, indent=2)

    def save_batch(self, records: List[PlaceRecord]) -> int:
        """Lưu một danh sách bản ghi và trả về số lượng đã ghi."""
        count = 0
        for r in records:
            self.save_record(r)
            count += 1
        return count

