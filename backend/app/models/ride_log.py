from sqlalchemy import Column, Integer, Float, TIMESTAMP, ForeignKey, Boolean
from app.database.connection import Base

class RideLog(Base):
    __tablename__ = "ride_logs"
    ride_id = Column(Integer, ForeignKey("ride_requests.request_id"), primary_key=True)
    start_time = Column(TIMESTAMP)
    end_time = Column(TIMESTAMP, nullable=True)
    ride_distance = Column(Float, nullable=True)
    amount_suggested = Column(Float)
    amount_paid_cash = Column(Float, default=0.0)
    is_payment_confirmed = Column(Boolean, default=False)