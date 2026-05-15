from sqlalchemy import Column, Integer, String
from app.database.connection import Base

class Passenger(Base):
    __tablename__ = "passengers"
    passenger_id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String)
    type = Column(String) # ADULT, CHILD, VIP