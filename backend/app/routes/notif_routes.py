from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List
from app.database.connection import get_db
from app.schemas.notification import NotificationSchema
from app.controllers.notification_controller import NotificationController

router = APIRouter(
    prefix="/notifications",
    tags=["notifications"]
)

@router.get("/{user_id}", response_model=List[NotificationSchema])
def get_user_notifications(user_id: int, db: Session = Depends(get_db)):
    return NotificationController.get_user_notifications(db, user_id)

@router.patch("/{notification_id}/read")
def mark_as_read(notification_id: int, db: Session = Depends(get_db)):
    return NotificationController.mark_as_read(db, notification_id)

@router.delete("/{notification_id}")
def delete_notification(notification_id: int, db: Session = Depends(get_db)):
    return NotificationController.delete_notification(db, notification_id)