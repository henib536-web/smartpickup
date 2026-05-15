from sqlalchemy import Column, Integer, String, TIMESTAMP, ForeignKey, JSON
from app.database.connection import Base
from datetime import datetime

class RideEvent(Base):
    __tablename__ = "ride_events"
    event_id = Column(Integer, primary_key=True, index=True)
    ride_id = Column(Integer, ForeignKey("ride_requests.request_id"))
    event_type = Column(String)
    timestamp = Column(TIMESTAMP, default=datetime.utcnow)
    metadata_json = Column(JSON, nullable=True)