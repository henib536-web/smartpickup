from locust import HttpUser, task, between

class SmartPickupUser(HttpUser):
    # Temps d'attente entre chaque requête pour simuler un vrai utilisateur
    wait_time = between(1, 3)

    @task
    def view_available_rides(self):
        """
        Simule un chauffeur qui consulte la liste des courses disponibles.
        """
        # On suppose qu'un chauffeur a l'ID 52 par défaut pour ce test
        self.client.get("/api/driver/rides/available?driver_id=52")

    @task(2)
    def view_admin_stats(self):
        """
        Simule l'administrateur qui rafraîchit le tableau de bord.
        Le poids (2) indique que cette tâche a deux fois plus de chance d'être exécutée.
        """
        self.client.get("/api/admin/stats")
