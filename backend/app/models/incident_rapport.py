from sqlalchemy import Column, Integer, String, ForeignKey, DateTime
from app.database.connection import Base
from datetime import datetime

class IncidentReport(Base):
    __tablename__ = "incident_reports"
    report_id = Column(Integer, primary_key=True, index=True)
    ride_id = Column(Integer, ForeignKey("ride_requests.request_id"))
    report_type = Column(String)
    severity_level = Column(Integer)
    description = Column(String, nullable=True)
    status = Column(String, default="OPEN")
    resolution_note = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)