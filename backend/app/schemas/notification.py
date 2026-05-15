# app/schemas/notification.py
from pydantic import BaseModel
from datetime import datetime

class NotificationSchema(BaseModel):
    notification_id: int
    user_id: int
    title: str
    message: str
    type: str
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True