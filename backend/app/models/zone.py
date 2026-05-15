from sqlalchemy import Column, Integer, String
from app.database.connection import Base

class Zone(Base):
    __tablename__ = "zones"
    zone_id = Column(Integer, primary_key=True, index=True)
    zone_name = Column(String)
    city = Column(String)