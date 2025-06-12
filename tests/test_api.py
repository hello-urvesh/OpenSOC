
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient
from opensoc.main import app


def get_client():
    return TestClient(app)


def test_index():
    with get_client() as client:
        response = client.get("/")
        assert response.status_code == 200

def test_create_case():
    with get_client() as client:
        response = client.post(
            "/cases/new",
            data={"title": "Test Case", "description": "desc"},
            follow_redirects=False,
        )
        assert response.status_code == 303
