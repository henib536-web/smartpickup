import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_full_ride_lifecycle():
    """
    Test simulant le cycle complet d'une réservation entre le client et le chauffeur.
    """
    # 1. Création du trajet par le client (Endpoint : /rides/book)
    payload_book = {
        "client_id": 1,
        "passenger_name": "Test Client",
        "passenger_type": "client",
        "zone_name": "Tunis",
        "pickup_location": "Tunis Centre",
        "dropoff_location": "Aéroport Carthage",
        "pickup_lat": 36.8065,
        "pickup_lng": 10.1815,
        "dropoff_lat": 36.8510,
        "dropoff_lng": 10.2272,
        "pickup_time": "2026-06-10T10:00:00Z",
        "scheduled_flag": False,
        "distance_km": 7.5,
        "estimated_price": 8150
    }
    
    response = client.post("/rides/book", json=payload_book)
    # Vérification que le trajet a bien été créé
    assert response.status_code == 201
    ride_id = response.json().get("request_id")
    assert response.json().get("status") == "success"

    # Vérification que le chauffeur reçoit la course avec son prix estimé et prix de base
    response_available = client.get("/api/driver/rides/available?driver_id=52")
    assert response_available.status_code == 200
    rides = response_available.json()
    assert len(rides) > 0
    my_ride = next((r for r in rides if r["request_id"] == ride_id), None)
    assert my_ride is not None, "La course devrait être disponible pour le chauffeur"
    assert "estimated_price" in my_ride
    assert "base_price" in my_ride
    assert my_ride["estimated_price"] == 8150
    assert my_ride["base_price"] == 3500

    # 2. Acceptation par le chauffeur (Endpoint : /api/driver/rides/{id}/accept)
    # L'ID du chauffeur est passé en paramètre
    response = client.post(f"/api/driver/rides/{ride_id}/accept?driver_id=52")
    assert response.status_code == 200
    
    # 3. Démarrage de la course (Endpoint : /api/driver/rides/{id}/status)
    response = client.put(f"/api/driver/rides/{ride_id}/status", json={"action": "start"})
    assert response.status_code == 200
    
    # 4. Finalisation de la course (Endpoint : /api/driver/rides/{id}/status)
    response = client.put(f"/api/driver/rides/{ride_id}/status", json={"action": "complete"})
    assert response.status_code == 200

def test_ride_cancellation():
    """
    Test d'intégration pour l'annulation de course.
    """
    payload_book = {
        "client_id": 1,
        "passenger_name": "Test Cancel",
        "passenger_type": "client",
        "zone_name": "Tunis",
        "pickup_location": "Tunis Centre",
        "dropoff_location": "Aéroport Carthage",
        "pickup_lat": 36.8,
        "pickup_lng": 10.1,
        "dropoff_lat": 36.85,
        "dropoff_lng": 10.2,
        "pickup_time": "2026-06-10T10:00:00Z",
        "scheduled_flag": False,
        "distance_km": 5.0
    }
    
    # 1. Création d'une course
    response = client.post("/rides/book", json=payload_book)
    assert response.status_code == 201
    ride_id = response.json().get("request_id")
    
    # 2. Annulation réussie de la course
    cancel_res = client.post(f"/rides/{ride_id}/cancel")
    assert cancel_res.status_code == 200
    assert cancel_res.json().get("status") == "success"
    
    # 3. Vérification dans l'historique du client (l'endpoint est dans les routes rides)
    # Actually, the user rides endpoint is GET /rides/user/{client_id}
    history_res = client.get("/rides/user/1")
    assert history_res.status_code == 200
    canceled_ride = next((r for r in history_res.json() if r["request_id"] == ride_id), None)
    assert canceled_ride is not None
    assert canceled_ride["status"] == "CANCELLED"
