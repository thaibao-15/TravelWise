"""
TravelWise — Script kiểm tra kết nối Chat LLM Model (Task 3.1).

Cách chạy:
    uv run python scripts/test_llm.py
"""

import sys
from pathlib import Path

# Add project root (apps/api) to sys.path
api_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(api_root))

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

from fastapi.testclient import TestClient
from app.core.config import settings
from app.main import app


def run_checks():
    print("=" * 60)
    print(" TravelWise - Kiểm tra kết nối Chat LLM (Task 3.1)")
    print("=" * 60)

    provider = (settings.LLM_PROVIDER or "gemini").lower()
    print(f"\n[1] Cấu hình hiện tại:")
    print(f"    - LLM_PROVIDER: {provider}")

    if provider == "gemini":
        active_model = settings.GEMINI_MODEL
        key = settings.GEMINI_API_KEY
    else:
        active_model = settings.OPENAI_MODEL
        key = settings.OPENAI_API_KEY

    print(f"    - MODEL       : {active_model}")
    key_configured = bool(key and key.strip())
    masked_key = f"{key[:7]}...{key[-4:]}" if key_configured else "Chưa cấu hình"
    print(f"    - API_KEY     : {masked_key}")

    # 2. Test gọi qua FastAPI TestClient
    print("\n[2] Test FastAPI endpoint POST /rag/test-llm:")
    client = TestClient(app)

    if not key_configured:
        print(f"    (!) Chưa cấu hình API key cho provider '{provider}' trong .env.")
        print("    -> Đang kiểm tra phản hồi lỗi an toàn của FastAPI khi chưa có key...")
        res = client.post("/rag/test-llm", json={"prompt": "Ping"})
        if res.status_code == 500:
            print("    [PASS] FastAPI bắt lỗi an toàn (HTTP 500) và không để lộ thông tin nhạy cảm.")
            print(f"    Phản hồi: {res.json()}")
        else:
            print(f"    [FAIL] Status code không mong muốn: {res.status_code}, response: {res.text}")
        return

    # Nếu đã có key thật
    print("    -> Đang gửi test prompt tới FastAPI endpoint /rag/test-llm...")
    test_prompt = "Xin chào, hãy trả lời ngắn gọn: bạn là ai và đã sẵn sàng hỗ trợ ứng dụng TravelWise chưa?"
    try:
        res = client.post("/rag/test-llm", json={"prompt": test_prompt})
        if res.status_code == 200:
            data = res.json()
            print("    [PASS] Kết nối LLM qua FastAPI thành công (HTTP 200)!")
            print(f"    - Provider : {data.get('provider')}")
            print(f"    - Model    : {data.get('model')}")
            print(f"    - Phản hồi từ LLM:\n      \"{data.get('response')}\"")
        else:
            print(f"    [FAIL] Gọi API thất bại: HTTP {res.status_code}")
            print(f"    Chi tiết: {res.json()}")
    except Exception as e:
        print(f"    [ERROR] Lỗi khi gọi endpoint: {type(e).__name__}")


if __name__ == "__main__":
    run_checks()
