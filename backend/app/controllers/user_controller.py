from typing import Optional
from fastapi import UploadFile, HTTPException
from sqlalchemy.orm import Session
import os
import shutil
import uuid
from datetime import datetime

from app.models.user import User
from app.models.passenger import Passenger
from app.models.notification import NotificationModel
from app.services.auth_service import verify_password, get_password_hash, _verify_code_or_raise
from app.services.notification_service import send_push_notification

UPLOAD_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "uploads"))
os.makedirs(UPLOAD_DIR, exist_ok=True)

class UserController:
    @staticmethod
    def save_upload_file(upload_file: Optional[UploadFile]) -> Optional[str]:
        if upload_file is None or not upload_file.filename:
            return None

        extension = os.path.splitext(upload_file.filename)[1] or ".jpg"
        filename = f"{uuid.uuid4().hex}{extension}"
        destination = os.path.join(UPLOAD_DIR, filename)

        with open(destination, "wb") as buffer:
            shutil.copyfileobj(upload_file.file, buffer)

        return f"/uploads/{filename}"

    @staticmethod
    def get_profile(db: Session, user_id: int):
        user = db.query(User).filter(User.user_id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="Utilisateur non trouvé")

        return {
            "user_id": user.user_id,
            "full_name": user.full_name,
            "email": user.email,
            "phone": user.phone,
            "image_url": user.image_url,
            "created_at": user.created_at.strftime("%B %Y") if user.created_at else "Janvier 2026",
            "role": user.role.value if user.role else None,
        }

    @staticmethod
    def update_profile(
        db: Session,
        user_id: int,
        full_name: str,
        email: str,
        phone: str,
        current_password: str,
        profile_image: Optional[UploadFile] = None
    ):
        user = db.query(User).filter(User.user_id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="Utilisateur non trouvé")

        if not verify_password(current_password, user.password_hash):
            raise HTTPException(status_code=400, detail="Mot de passe incorrect")

        email_owner = db.query(User).filter(User.email == email, User.user_id != user_id).first()
        if email_owner:
            raise HTTPException(status_code=400, detail="Cet email est deja utilise")

        user.full_name = full_name
        user.email = email
        user.phone = phone
        user.updated_at = user.updated_at or user.created_at

        image_url = UserController.save_upload_file(profile_image)
        if image_url:
            user.image_url = image_url

        passenger = db.query(Passenger).filter(Passenger.passenger_id == user_id).first()
        if passenger:
            passenger.full_name = full_name

        db.commit()
        db.refresh(user)

        return {
            "status": "success",
            "user_id": user.user_id,
            "full_name": user.full_name,
            "email": user.email,
            "phone": user.phone,
            "image_url": user.image_url,
        }

    @staticmethod
    def change_password(db: Session, user_id: int, payload):
        user = db.query(User).filter(User.user_id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="Utilisateur non trouvé")
        
        if payload.old_password:
            if not verify_password(payload.old_password, user.password_hash):
                raise HTTPException(status_code=400, detail="L'ancien mot de passe est incorrect")
        elif payload.code:
            _verify_code_or_raise(db, user.email, payload.code, "password_reset")
        else:
            raise HTTPException(status_code=400, detail="L'ancien mot de passe ou un code est requis")
            
        user.password_hash = get_password_hash(payload.new_password)
        db.commit()
        
        return {"status": "success", "message": "Mot de passe mis à jour avec succès"}

    @staticmethod
    def update_fcm_token(db: Session, user_id: int, fcm_token: str | None):
        if fcm_token:
            db.query(User).filter(User.fcm_token == fcm_token, User.user_id != user_id).update({"fcm_token": None})
            
        user = db.query(User).filter(User.user_id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="Utilisateur non trouvé")
        
        user.fcm_token = fcm_token
        db.commit()
        
        return {"status": "success", "message": "Token FCM mis à jour"}

    @staticmethod
    def test_notification(db: Session, user_id: int):
        user = db.query(User).filter(User.user_id == user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="Utilisateur non trouvé")
        
        if not user.fcm_token:
            raise HTTPException(status_code=400, detail="Cet utilisateur n'a pas de token FCM d'enregistré")
            
        title = "🔔 Test Notification"
        body = f"Bonjour {user.full_name}, vos notifications fonctionnent parfaitement !"

        # 1. Enregistrer dans la base de données
        new_notif = NotificationModel(
            user_id=user_id,
            title=title,
            message=body,
            type="test_ping",
            created_at=datetime.now()
        )
        db.add(new_notif)
        db.commit()

        # 2. Envoyer le Push
        success = send_push_notification(
            fcm_token=user.fcm_token,
            title=title,
            body=body,
            data={"type": "test_ping"}
        )
        
        if success:
            return {"status": "success", "message": "Notification envoyée avec succès ! Regardez votre téléphone."}
        else:
            raise HTTPException(status_code=500, detail="Erreur lors de l'envoi. Vérifiez la console du backend.")