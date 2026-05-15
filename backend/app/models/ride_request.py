from sqlalchemy import Column, Integer, String, TIMESTAMP, DECIMAL, ForeignKey, Enum
from app.database.connection import Base
from .base_enums import RideStatusEnum, CancelledBy
from datetime import datetime

class RideRequest(Base):
    __tablename__ = "ride_requests"
    request_id = Column(Integer, primary_key=True, index=True)
    client_id = Column(Integer, ForeignKey("clients.client_id"))
    passenger_id = Column(Integer, ForeignKey("passengers.passenger_id"))
    zone_id = Column(Integer, ForeignKey("zones.zone_id"))
    schedule_id = Column(Integer, ForeignKey("recurring_schedules.schedule_id"), nullable=True)
    
    requested_at = Column(TIMESTAMP, default=datetime.utcnow)
    scheduled_for = Column(TIMESTAMP)
    pickup_location = Column(String)
    dropoff_location = Column(String)
    pickup_lat = Column(DECIMAL(10, 8))
    pickup_lng = Column(DECIMAL(11, 8))
    dropoff_lat = Column(DECIMAL(10, 8))
    dropoff_lng = Column(DECIMAL(11, 8))
    
    status = Column(Enum(RideStatusEnum), default=RideStatusEnum.PENDING)
    priority_price = Column(DECIMAL(10, 2), default=2.0)
    cancellation_reason = Column(String, nullable=True)
    cancelled_by = Column(Enum(CancelledBy), nullable=True)