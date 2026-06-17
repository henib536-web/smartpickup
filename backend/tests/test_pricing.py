import pytest
from app.controllers.ride_controller import RideController

def test_calculate_price_logic():
    """
    Test de la fonction de calcul de prix pour s'assurer que :
    - Le prix de base n'est jamais inférieur à 3500 millimes.
    - Le priority_price est bien appliqué s'il est supérieur à 3500.
    """
    # Cas 1 : Tentative de fixer un prix de base trop bas (2000 millimes)
    # Formule attendue : 3500 (minimum forcé) + (10km * 500) + 900 = 9400
    prix_1 = RideController.calculate_price(distance_km=10.0, base_price=2000)
    assert prix_1 == 9400

    # Cas 2 : Le client offre un pourboire/prix de priorité (5000 millimes)
    # Formule attendue : 5000 + (10km * 500) + 900 = 10900
    prix_2 = RideController.calculate_price(distance_km=10.0, base_price=5000)
    assert prix_2 == 10900

    # Cas 3 : Sans distance (fallback)
    # Formule attendue : 3500 + 0 + 900 = 4400
    prix_3 = RideController.calculate_price(distance_km=0.0, base_price=3500)
    assert prix_3 == 4400
