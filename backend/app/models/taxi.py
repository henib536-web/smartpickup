from sqlalchemy import Column, Integer, String, Boolean, ForeignKey
from app.database.connection import Base

class Taxi(Base):
    __tablename__ = "taxis"
    taxi_id = Column(Integer, primary_key=True, index=True)
    driver_id = Column(Integer, ForeignKey("drivers.driver_id"))
    plate_number = Column(String, unique=True)
    vehicle_model = Column(String)
    availability = Column(Boolean, default=True)