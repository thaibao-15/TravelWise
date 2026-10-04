import unittest
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.core.security import create_access_token
from app.db.session import engine
from app.main import app
from app.models.user import User


class TestConversationMemory(unittest.TestCase):
    """Integration test suite for Conversation Memory & RAG Chat Flow (Section 11)."""

    def setUp(self):
        self.client = TestClient(app)

        with Session(engine) as session:
            user_a = session.exec(select(User).where(User.email == "usera_test@example.com")).first()
            if not user_a:
                user_a = User(email="usera_test@example.com", full_name="User A Test", role="USER", is_active=True)
                session.add(user_a)
                session.commit()
                session.refresh(user_a)

            user_b = session.exec(select(User).where(User.email == "userb_test@example.com")).first()
            if not user_b:
                user_b = User(email="userb_test@example.com", full_name="User B Test", role="USER", is_active=True)
                session.add(user_b)
                session.commit()
                session.refresh(user_b)

            self.user_a_id = user_a.id
            self.user_b_id = user_b.id

        self.token_a = create_access_token(subject=self.user_a_id, email="usera_test@example.com", role="USER")
        self.token_b = create_access_token(subject=self.user_b_id, email="userb_test@example.com", role="USER")

        self.headers_a = {"Authorization": f"Bearer {self.token_a}"}
        self.headers_b = {"Authorization": f"Bearer {self.token_b}"}

    def test_full_conversation_memory_and_authorization_flow(self):
        # 1. Test 1: User A starts conversation: "Chùa Linh Ứng nằm ở đâu?"
        resp1 = self.client.post(
            "/api/v1/rag/ask",
            json={"message": "Chùa Linh Ứng nằm ở đâu?"},
            headers=self.headers_a,
        )
        self.assertEqual(resp1.status_code, 200)
        data1 = resp1.json()
        conv_id = data1.get("conversation_id")
        self.assertIsNotNone(conv_id)

        # 2. Test 2: Same conversation: "Nó có gì đặc biệt?"
        resp2 = self.client.post(
            "/api/v1/rag/ask",
            json={"conversation_id": conv_id, "message": "Nó có gì đặc biệt?"},
            headers=self.headers_a,
        )
        self.assertEqual(resp2.status_code, 200)
        data2 = resp2.json()
        self.assertEqual(data2.get("conversation_id"), conv_id)

        # 3. Test 3: Switch context: "Còn Đèo Hải Vân thì sao?"
        resp3 = self.client.post(
            "/api/v1/rag/ask",
            json={"conversation_id": conv_id, "message": "Còn Đèo Hải Vân thì sao?"},
            headers=self.headers_a,
        )
        self.assertEqual(resp3.status_code, 200)

        # 4. Test 4: Pronoun under new context: "Nó cách Đà Nẵng bao xa?"
        resp4 = self.client.post(
            "/api/v1/rag/ask",
            json={"conversation_id": conv_id, "message": "Nó cách Đà Nẵng bao xa?"},
            headers=self.headers_a,
        )
        self.assertEqual(resp4.status_code, 200)

        # 5. Test 5: Create new conversation 2
        resp_new = self.client.post(
            "/api/v1/conversations/",
            json={"title": "Cuộc hội thoại mới độc lập"},
            headers=self.headers_a,
        )
        self.assertEqual(resp_new.status_code, 201)
        conv_2_id = resp_new.json()["id"]

        resp5 = self.client.post(
            "/api/v1/rag/ask",
            json={"conversation_id": conv_2_id, "message": "Nó có gì đặc biệt?"},
            headers=self.headers_a,
        )
        self.assertEqual(resp5.status_code, 200)

        # 6. Test 6: User B attempts unauthorized access
        resp6_ask = self.client.post(
            "/api/v1/rag/ask",
            json={"conversation_id": conv_id, "message": "Hack attempt"},
            headers=self.headers_b,
        )
        self.assertEqual(resp6_ask.status_code, 403)

        resp6_get = self.client.get(f"/api/v1/conversations/{conv_id}", headers=self.headers_b)
        self.assertEqual(resp6_get.status_code, 403)

        resp6_msgs = self.client.get(f"/api/v1/conversations/{conv_id}/messages", headers=self.headers_b)
        self.assertEqual(resp6_msgs.status_code, 403)

        resp6_del = self.client.delete(f"/api/v1/conversations/{conv_id}", headers=self.headers_b)
        self.assertEqual(resp6_del.status_code, 403)


if __name__ == "__main__":
    unittest.main()
