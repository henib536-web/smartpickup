from sqlalchemy import Column, Integer, String, TIMESTAMP, ForeignKey
from app.database.connection import Base
from datetime import datetime

class RideRating(Base):
    __tablename__ = "ride_ratings"
    rating_id = Column(Integer, primary_key=True, index=True)
    ride_id = Column(Integer, ForeignKey("ride_logs.ride_id"))
    user_id = Column(Integer, ForeignKey("users.user_id"))
    driver_id = Column(Integer, ForeignKey("drivers.driver_id"))
    rating = Column(Integer)
    comment = Column(String, nullable=True)
    created_at = Column(TIMESTAMP, default=datetime.utcnow)