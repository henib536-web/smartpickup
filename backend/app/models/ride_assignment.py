from sqlalchemy import Column, Integer, Boolean, TIMESTAMP, ForeignKey, Enum
from app.database.connection import Base
from .base_enums import AssignmentStatus
from datetime import datetime

class RideAssignment(Base):
    __tablename__ = "ride_assignments"
    assignment_id = Column(Integer, primary_key=True, index=True)
    request_id = Column(Integer, ForeignKey("ride_requests.request_id"))
    taxi_id = Column(Integer, ForeignKey("taxis.taxi_id"))
    status = Column(Enum(AssignmentStatus), default=AssignmentStatus.PENDING)
    offered_at = Column(TIMESTAMP, default=datetime.utcnow)
    responded_at = Column(TIMESTAMP, nullable=True)
    is_suggested = Column(Boolean, default=False)