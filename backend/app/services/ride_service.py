from sqlalchemy.orm import Session
from app.models.ride import RideRequest, RequestStatusEnum
from app.schemas.ride import RideCreate  # On va créer ce schéma juste après
from datetime import datetime

class RideService:
    @staticmethod
    def create_booking(db: Session, ride_data: dict):
        # Création de l'objet selon ton modèle SQLAlchemy
        new_ride = RideRequest(
            passenger_id=ride_data.get("passenger_id"),
            zone_id=ride_data.get("zone_id", 1), # Zone par défaut
            pickup_location=ride_data.get("pickup_location"),
            dropoff_location=ride_data.get("dropoff_location"),
            pickup_lat=ride_data.get("pickup_lat"),
            pickup_lng=ride_data.get("pickup_lng"),
            dropoff_lat=ride_data.get("dropoff_lat"),
            dropoff_lng=ride_data.get("dropoff_lng"),
            pickup_time=datetime.fromisoformat(ride_data.get("pickup_time")),
            scheduled_flag=ride_data.get("scheduled_flag", False),
            status=RequestStatusEnum.pending,
            created_at=datetime.utcnow()
        )
        
        db.add(new_ride)
        db.commit()
        db.refresh(new_ride)
        return new_ride