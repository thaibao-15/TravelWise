import unittest

from app.api.routes.rag import get_planning_signals


class TestPlanningSignals(unittest.TestCase):
    def test_explicit_and_natural_itinerary_requests_trigger_generation(self):
        planning_context = {
            "planning_state": {"is_ready_to_generate": True},
        }

        for question in (
            "Tạo lịch trình Đà Nẵng 3 ngày",
            "Mình muốn lên kế hoạch cho chuyến đi Đà Nẵng 3 ngày",
            "Cho mình lịch trình Đà Nẵng 3 ngày",
            "minh muon lich trinh Da Nang 3 ngay",
        ):
            with self.subTest(question=question):
                self.assertEqual(
                    get_planning_signals(question, planning_context),
                    ("ready_to_generate", True, "TRIGGER_GENERATION"),
                )

    def test_generation_requires_a_request_and_ready_context(self):
        ready_context = {
            "planning_state": {"is_ready_to_generate": True},
        }
        incomplete_context = {
            "planning_state": {"is_ready_to_generate": False},
        }

        self.assertIsNone(
            get_planning_signals(
                "Mình muốn đi Đà Nẵng 3 ngày",
                ready_context,
            )[2]
        )
        self.assertIsNone(
            get_planning_signals(
                "Lên kế hoạch đi Đà Nẵng",
                incomplete_context,
            )[2]
        )
        self.assertIsNone(
            get_planning_signals(
                "Lịch trình ở Cần Thơ có gì hay?",
                ready_context,
            )[2]
        )

    def test_save_and_edit_requests_keep_their_actions(self):
        planning_context = {
            "planning_state": {"is_ready_to_generate": True},
        }

        self.assertEqual(
            get_planning_signals("Lưu lịch trình này", planning_context)[2],
            "TRIGGER_SAVE",
        )
        self.assertEqual(
            get_planning_signals("Lưu lịch trình cho tôi", planning_context)[2],
            "TRIGGER_SAVE",
        )
        self.assertEqual(
            get_planning_signals("Chỉnh sửa lịch trình", planning_context)[2],
            "TRIGGER_EDIT",
        )
        self.assertEqual(
            get_planning_signals(
                "Giúp mình chỉnh sửa lịch trình",
                planning_context,
            )[2],
            "TRIGGER_EDIT",
        )


if __name__ == "__main__":
    unittest.main()
