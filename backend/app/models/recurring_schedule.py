from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, Enum, Date, Time, DECIMAL
from app.database.connection import Base
from .base_enums import DayOfWeek

class RecurringSchedule(Base):
    __tablename__ = "recurring_schedules"
    schedule_id = Column(Integer, primary_key=True, index=True)
    client_id = Column(Integer, ForeignKey("clients.client_id"))
    zone_id = Column(Integer, ForeignKey("zones.zone_id"))
    day_of_week = Column(Enum(DayOfWeek))
    start_date = Column(Date)
    end_date = Column(Date)
    pickup_time = Column(Time)
    pickup_location = Column(String)
    dropoff_location = Column(String)
    pickup_lat = Column(DECIMAL(10, 8), nullable=True)
    pickup_lng = Column(DECIMAL(11, 8), nullable=True)
    dropoff_lat = Column(DECIMAL(10, 8), nullable=True)
    dropoff_lng = Column(DECIMAL(11, 8), nullable=True)
    is_active = Column(Boolean, default=True)
    priority_price = Column(DECIMAL(10, 2), default=2.0)