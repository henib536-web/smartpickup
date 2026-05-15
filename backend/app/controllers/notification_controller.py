from fastapi import HTTPException
from sqlalchemy.orm import Session
from app.models.notification import NotificationModel

class NotificationController:
    @staticmethod
    def get_user_notifications(db: Session, user_id: int):
        return db.query(NotificationModel).filter(NotificationModel.user_id == user_id).all()

    @staticmethod
    def mark_as_read(db: Session, notification_id: int):
        db_notif = db.query(NotificationModel).filter(NotificationModel.notification_id == notification_id).first()
        if not db_notif:
            raise HTTPException(status_code=404, detail="Notification non trouvée")
        db_notif.is_read = True
        db.commit()
        db.refresh(db_notif)
        return {"status": "success", "message": "Notification marquée comme lue"}

    @staticmethod
    def delete_notification(db: Session, notification_id: int):
        result = db.query(NotificationModel).filter(NotificationModel.notification_id == notification_id).delete()
        if result == 0:
            raise HTTPException(status_code=404, detail="Notification non trouvée")
        db.commit()
        return {"status": "deleted"}
