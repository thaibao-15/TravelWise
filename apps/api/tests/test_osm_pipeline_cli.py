import tempfile
import json
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

from sqlmodel import Session, SQLModel, create_engine

from app.models.category import Category
from scripts.import_osm_restaurants import (
    run_fetch_step,
    run_normalize_step,
    run_import_step,
    run_pipeline,
)


class TestOSMPipelineCLI(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmpdir.name)
        self.raw_file = self.tmp_path / "raw.json"
        self.norm_file = self.tmp_path / "norm.json"

        # In-memory SQLite DB
        self.engine = create_engine("sqlite:///:memory:")
        SQLModel.metadata.create_all(self.engine)
        with Session(self.engine) as session:
            session.add(Category(id=1, name="Ẩm thực", description="Food"))
            session.commit()

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    @patch("scripts.import_osm_restaurants.fetch_raw_osm")
    def test_run_fetch_step_success(self, mock_fetch: MagicMock) -> None:
        mock_fetch.return_value = {
            "version": 0.6,
            "elements": [
                {
                    "type": "node",
                    "id": 1,
                    "lat": 16.0,
                    "lon": 108.0,
                    "tags": {"name": "Test Restaurant"},
                }
            ],
        }
        bbox = {"south": 15.9, "west": 107.8, "north": 16.3, "east": 108.4}
        ok = run_fetch_step(self.raw_file, bbox, timeout_seconds=10)
        self.assertTrue(ok)
        self.assertTrue(self.raw_file.exists())

    @patch("scripts.import_osm_restaurants.fetch_raw_osm")
    def test_run_fetch_step_failure_preserves_state(self, mock_fetch: MagicMock) -> None:
        mock_fetch.side_effect = RuntimeError("Overpass network timeout")
        bbox = {"south": 15.9, "west": 107.8, "north": 16.3, "east": 108.4}
        ok = run_fetch_step(self.raw_file, bbox, timeout_seconds=10)
        self.assertFalse(ok)
        self.assertFalse(self.raw_file.exists())

    def test_run_normalize_step_success(self) -> None:
        raw_payload = {
            "elements": [
                {
                    "type": "node",
                    "id": 101,
                    "lat": 16.05,
                    "lon": 108.20,
                    "tags": {"name": "Quán Bún Chả", "cuisine": "vietnamese"},
                },
                {
                    "type": "node",
                    "id": 102,
                    "lat": 16.05,
                    "lon": 108.20,
                    "tags": {},  # Discarded: missing name
                },
            ]
        }
        with open(self.raw_file, "w", encoding="utf-8") as f:
            json.dump(raw_payload, f)

        ok, records = run_normalize_step(self.raw_file, self.norm_file)
        self.assertTrue(ok)
        self.assertIsNotNone(records)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["osm_id"], 101)
        self.assertTrue(self.norm_file.exists())

    def test_run_normalize_step_missing_file(self) -> None:
        missing_path = self.tmp_path / "non_existent.json"
        ok, records = run_normalize_step(missing_path, self.norm_file)
        self.assertFalse(ok)
        self.assertIsNone(records)

    @patch("scripts.import_osm_restaurants.engine")
    def test_run_import_step_dry_run(self, mock_engine: MagicMock) -> None:
        mock_engine.connect = self.engine.connect
        mock_engine.begin = self.engine.begin
        mock_engine.dialect = self.engine.dialect

        records = [
            {
                "osm_id": 999,
                "osm_type": "node",
                "name": "Dry Run Restaurant",
                "latitude": 16.0,
                "longitude": 108.0,
            }
        ]
        ok = run_import_step(records, "Test Fixture", dry_run=True)
        self.assertTrue(ok)

    @patch("scripts.import_osm_restaurants.run_fetch_step")
    @patch("scripts.import_osm_restaurants.run_normalize_step")
    @patch("scripts.import_osm_restaurants.run_import_step")
    def test_pipeline_halts_immediately_on_fetch_failure(
        self,
        mock_import: MagicMock,
        mock_norm: MagicMock,
        mock_fetch: MagicMock,
    ) -> None:
        # Step 1 fails
        mock_fetch.return_value = False

        bbox = {"south": 15.9, "west": 107.8, "north": 16.3, "east": 108.4}
        result = run_pipeline(
            raw_path=self.raw_file,
            normalized_path=self.norm_file,
            bbox=bbox,
            limit=None,
            dry_run=False,
            skip_fetch=False,
        )

        self.assertFalse(result)
        mock_fetch.assert_called_once()
        # Step 2 and 3 must NEVER be called if step 1 fails
        mock_norm.assert_not_called()
        mock_import.assert_not_called()

    @patch("scripts.import_osm_restaurants.run_fetch_step")
    @patch("scripts.import_osm_restaurants.run_normalize_step")
    @patch("scripts.import_osm_restaurants.run_import_step")
    def test_pipeline_halts_on_normalize_failure(
        self,
        mock_import: MagicMock,
        mock_norm: MagicMock,
        mock_fetch: MagicMock,
    ) -> None:
        mock_fetch.return_value = True
        # Step 2 fails
        mock_norm.return_value = (False, None)

        bbox = {"south": 15.9, "west": 107.8, "north": 16.3, "east": 108.4}
        result = run_pipeline(
            raw_path=self.raw_file,
            normalized_path=self.norm_file,
            bbox=bbox,
            limit=None,
            dry_run=False,
            skip_fetch=False,
        )

        self.assertFalse(result)
        mock_fetch.assert_called_once()
        mock_norm.assert_called_once()
        # Step 3 must NEVER be called if step 2 fails
        mock_import.assert_not_called()


if __name__ == "__main__":
    unittest.main()
