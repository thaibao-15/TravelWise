"""
Script: fetch_osm_hotels.py
Description: Fetch hotel data from OpenStreetMap Overpass API for the Da Nang bounding box
             and save the raw JSON response to apps/api/data/osm_hotels_raw.json.

Usage:
    uv run python scripts/fetch_osm_hotels.py
    # or with custom options:
    uv run python scripts/fetch_osm_hotels.py --output data/osm_hotels_raw.json --timeout 60
    # or view report from existing file without re-fetching:
    uv run python scripts/fetch_osm_hotels.py --from-file data/osm_hotels_raw.json
"""

import argparse
import json
import logging
import os
from pathlib import Path
import sys
import time
from typing import Any, Optional

import httpx

# Add project root (apps/api) to sys.path
api_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(api_root))

from app.core.config import settings

# Force UTF-8 on Windows stdout if possible
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("fetch_osm_hotels")

# Default Bounding Box for Da Nang
DEFAULT_BBOX = {
    "south": 15.9,
    "west": 107.8,
    "north": 16.3,
    "east": 108.4,
}

OVERPASS_API_URL = getattr(settings, "OVERPASS_API_URL", "https://overpass-api.de/api/interpreter")
DEFAULT_OUTPUT_FILE = api_root / "data" / "osm_hotels_raw.json"


def build_overpass_query(bbox: dict[str, float], timeout_seconds: int = 60) -> str:
    """Build Overpass QL query for hotels (tourism=hotel) in bounding box."""
    bbox_str = f"{bbox['south']},{bbox['west']},{bbox['north']},{bbox['east']}"
    return (
        f"[out:json][timeout:{timeout_seconds}];\n"
        f"(\n"
        f'  node["tourism"="hotel"]({bbox_str});\n'
        f'  way["tourism"="hotel"]({bbox_str});\n'
        f'  relation["tourism"="hotel"]({bbox_str});\n'
        f");\n"
        f"out body center;\n"
    )


def extract_coordinates(element: dict[str, Any]) -> tuple[Optional[float], Optional[float]]:
    """Extract lat/lon from node directly or center dict for way/relation."""
    if "lat" in element and "lon" in element:
        try:
            return float(element["lat"]), float(element["lon"])
        except (ValueError, TypeError):
            pass

    center = element.get("center")
    if isinstance(center, dict) and "lat" in center and "lon" in center:
        try:
            return float(center["lat"]), float(center["lon"])
        except (ValueError, TypeError):
            pass

    return None, None


def fetch_raw_osm_hotels(
    bbox: dict[str, float],
    timeout_seconds: int = 60,
    max_retries: int = 3,
    initial_backoff: float = 3.0,
) -> dict[str, Any]:
    """Execute HTTP POST to Overpass API with retry and backoff on transient errors."""
    query = build_overpass_query(bbox, timeout_seconds=timeout_seconds)
    headers = {
        "User-Agent": "TravelWise-OSM-Importer/1.0 (contact: info@travelwise.local)",
        "Accept": "application/json",
    }

    attempt = 0
    backoff = initial_backoff

    print(f"📡 Sending Overpass hotel query to {OVERPASS_API_URL}...")
    print(f"📍 Bounding Box: {bbox}")

    with httpx.Client(timeout=float(timeout_seconds)) as client:
        while True:
            attempt += 1
            try:
                print(f"⏳ Attempt {attempt}/{max_retries + 1}...")
                response = client.post(
                    OVERPASS_API_URL,
                    data={"data": query},
                    headers=headers,
                )

                # Retry on HTTP 429 (Too Many Requests) or 5xx server issues
                if response.status_code in {429, 500, 502, 503, 504}:
                    if attempt <= max_retries:
                        print(
                            f"⚠️  Overpass API returned HTTP {response.status_code}. "
                            f"Retrying in {backoff:.1f}s (backoff)..."
                        )
                        time.sleep(backoff)
                        backoff *= 2.0
                        continue
                    response.raise_for_status()

                response.raise_for_status()

                # Parse JSON
                try:
                    data = response.json()
                except ValueError as json_err:
                    raise RuntimeError(f"Overpass API returned invalid JSON: {json_err}") from json_err

                if not isinstance(data, dict) or "elements" not in data:
                    raise RuntimeError("Overpass response missing expected 'elements' array")

                return data

            except (httpx.TimeoutException, httpx.NetworkError) as net_err:
                if attempt <= max_retries:
                    print(
                        f"⚠️  Network / Timeout error ({type(net_err).__name__}: {net_err}). "
                        f"Retrying in {backoff:.1f}s..."
                    )
                    time.sleep(backoff)
                    backoff *= 2.0
                    continue
                raise RuntimeError(
                    f"Overpass API request failed after {attempt} attempts: {net_err}"
                ) from net_err

            except httpx.HTTPStatusError as http_err:
                raise RuntimeError(
                    f"Overpass API returned unrecoverable HTTP status {http_err.response.status_code}"
                ) from http_err


def save_atomic_json(data: dict[str, Any], output_path: Path) -> None:
    """Save JSON data to output_path atomically via a temporary file to prevent corruption."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = output_path.with_suffix(f"{output_path.suffix}.tmp")

    try:
        with open(temp_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.replace(temp_path, output_path)
    finally:
        if temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass


def verify_and_report(file_path: Path) -> bool:
    """Verify saved JSON file and print detailed statistics and sample records."""
    if not file_path.exists():
        print(f"❌ Verification failed: File {file_path} does not exist.")
        return False

    file_size_kb = file_path.stat().st_size / 1024
    print(f"\n========================================================")
    print(f"📊 VERIFICATION REPORT: {file_path.name}")
    print(f"📁 Path: {file_path.resolve()}")
    print(f"💾 File size: {file_size_kb:.2f} KB")

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:
        print(f"❌ Failed to parse JSON file: {exc}")
        return False

    elements: list[dict[str, Any]] = data.get("elements", [])
    total_count = len(elements)
    print(f"🔢 Total elements in response: {total_count}")

    # Count by type
    nodes = [e for e in elements if e.get("type") == "node"]
    ways = [e for e in elements if e.get("type") == "way"]
    relations = [e for e in elements if e.get("type") == "relation"]

    print(f"   • Nodes     : {len(nodes)}")
    print(f"   • Ways      : {len(ways)}")
    print(f"   • Relations : {len(relations)}")

    # Count elements with name
    named_elements = [
        e
        for e in elements
        if (
            isinstance(e.get("tags"), dict)
            and (
                e["tags"].get("name")
                or e["tags"].get("name:vi")
                or e["tags"].get("name:en")
            )
        )
    ]
    pct = (len(named_elements) / total_count * 100) if total_count else 0.0
    print(f"   • Elements with name: {len(named_elements)} ({pct:.1f}%)")

    # Count elements with stars
    elements_with_stars = [
        e for e in elements
        if isinstance(e.get("tags"), dict) and e["tags"].get("stars")
    ]
    print(f"   • Elements with stars tag: {len(elements_with_stars)}")

    # Sample records
    print("\n🔍 5 Sample Records:")
    sample_items = named_elements[:5] if len(named_elements) >= 5 else elements[:5]
    for idx, item in enumerate(sample_items, 1):
        el_type = item.get("type")
        el_id = item.get("id")
        tags = item.get("tags") or {}
        name = tags.get("name") or tags.get("name:vi") or tags.get("name:en") or "<No name>"
        lat, lon = extract_coordinates(item)
        stars = tags.get("stars") or "<None>"
        tourism = tags.get("tourism") or "<None>"

        print(f"  {idx}. [{el_type.upper()}] ID: {el_id}")
        print(f"     Name      : {name}")
        print(f"     Coords    : lat={lat}, lon={lon}")
        print(f"     Tourism   : {tourism} | Stars: {stars}")

    print(f"========================================================\n")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch hotel data from OpenStreetMap Overpass API for Da Nang."
    )
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        default=str(DEFAULT_OUTPUT_FILE),
        help=f"Output JSON file path (default: {DEFAULT_OUTPUT_FILE})",
    )
    parser.add_argument(
        "--from-file",
        type=str,
        default=None,
        help="Skip Overpass API query and verify an existing raw JSON file",
    )
    parser.add_argument(
        "--timeout",
        "-t",
        type=int,
        default=60,
        help="HTTP timeout in seconds (default: 60)",
    )
    parser.add_argument(
        "--retries",
        "-r",
        type=int,
        default=3,
        help="Maximum retries for network / rate limit errors (default: 3)",
    )
    parser.add_argument(
        "--south",
        type=float,
        default=DEFAULT_BBOX["south"],
        help=f"Bbox south (default: {DEFAULT_BBOX['south']})",
    )
    parser.add_argument(
        "--west",
        type=float,
        default=DEFAULT_BBOX["west"],
        help=f"Bbox west (default: {DEFAULT_BBOX['west']})",
    )
    parser.add_argument(
        "--north",
        type=float,
        default=DEFAULT_BBOX["north"],
        help=f"Bbox north (default: {DEFAULT_BBOX['north']})",
    )
    parser.add_argument(
        "--east",
        type=float,
        default=DEFAULT_BBOX["east"],
        help=f"Bbox east (default: {DEFAULT_BBOX['east']})",
    )

    args = parser.parse_args()

    # If --from-file is provided, directly verify and report without calling Overpass
    if args.from_file:
        file_path = Path(args.from_file).resolve()
        print(f"📂 Reading existing OSM hotel raw data from {file_path}...")
        success = verify_and_report(file_path)
        if not success:
            sys.exit(1)
        return

    bbox = {
        "south": args.south,
        "west": args.west,
        "north": args.north,
        "east": args.east,
    }
    output_path = Path(args.output).resolve()

    try:
        raw_data = fetch_raw_osm_hotels(
            bbox=bbox,
            timeout_seconds=args.timeout,
            max_retries=args.retries,
        )

        print(f"💾 Saving raw hotel JSON to {output_path}...")
        save_atomic_json(raw_data, output_path)
        print("✅ File saved successfully.")

        success = verify_and_report(output_path)
        if not success:
            sys.exit(1)

    except Exception as exc:
        print(f"❌ Error fetching OSM hotel data: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
