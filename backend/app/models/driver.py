from sqlalchemy import Column, Integer, String, Boolean, Float, Date, ForeignKey, DateTime
from .user import User

class Driver(User):
    __tablename__ = "drivers"
    driver_id = Column(Integer, ForeignKey("users.user_id"), primary_key=True)
    license_number = Column(String)
    cin_card_photo = Column(String)
    license_expiry_date = Column(Date)
    driver_card_photo = Column(String)
    is_available = Column(Boolean, default=True)
    average_rating = Column(Float, default=5.0)
    current_lat = Column(Float, nullable=True)
    current_lng = Column(Float, nullable=True)
    last_location_update = Column(DateTime, nullable=True)

