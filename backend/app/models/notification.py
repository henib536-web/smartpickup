from sqlalchemy import Column, Integer, String, Boolean, TIMESTAMP, ForeignKey
from app.database.connection import Base

class NotificationModel(Base): # Nommé différemment pour éviter la confusion
    __tablename__ = "notifications"

    notification_id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.user_id"))
    title = Column(String)
    message = Column(String)
    type = Column(String)
    is_read = Column(Boolean, default=False)
    created_at = Column(TIMESTAMP)