import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_access_protected_route_without_token():
    """
    Test de sécurité : 
    Vérifier qu'un appel à une route protégée sans JWT Token est rejeté.
    """
    response = client.get("/auth/me")
    # L'API doit retourner 401 Unauthorized car aucun token n'est fourni
    assert response.status_code == 401
    assert response.json().get("detail") == "Not authenticated"

def test_login_with_invalid_credentials():
    """
    Test de sécurité :
    Vérifier que l'authentification échoue avec un mauvais mot de passe.
    """
    payload = {
        "email": "admin@smartpickup.com",
        "password": "wrongpassword123!"
    }
    response = client.post("/auth/login", json=payload)
    # Soit 401 soit 400 selon l'implémentation
    assert response.status_code in [400, 401, 404]
