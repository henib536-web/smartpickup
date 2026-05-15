from sqlalchemy import Column, Integer, String, ForeignKey
from app.database.connection import Base

class IncidentReport(Base):
    __tablename__ = "incident_reports"
    report_id = Column(Integer, primary_key=True, index=True)
    ride_id = Column(Integer, ForeignKey("ride_logs.ride_id"))
    report_type = Column(String)
    severity_level = Column(Integer)
    status = Column(String, default="OPEN")