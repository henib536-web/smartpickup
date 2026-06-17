from typing import Optional
from fastapi import APIRouter, Depends, File, Form, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database.connection import get_db
from app.controllers.user_controller import UserController

router = APIRouter(prefix="/users", tags=["users"])

class ChangePasswordRequest(BaseModel):
    old_password: Optional[str] = None
    code: Optional[str] = None
    new_password: str

class FcmTokenRequest(BaseModel):
    fcm_token: str


@router.get("/profile/{user_id}")
def get_profile(user_id: int, db: Session = Depends(get_db)):
    return UserController.get_profile(db, user_id)


@router.put("/profile/{user_id}")
async def update_profile(
    user_id: int,
    full_name: str = Form(...),
    email: str = Form(...),
    phone: str = Form(...),
    current_password: str = Form(...),
    profile_image: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
):
    return UserController.update_profile(
        db=db,
        user_id=user_id,
        full_name=full_name,
        email=email,
        phone=phone,
        current_password=current_password,
        profile_image=profile_image
    )


@router.put("/change-password/{user_id}")
def change_password(user_id: int, payload: ChangePasswordRequest, db: Session = Depends(get_db)):
    return UserController.change_password(db, user_id, payload)


@router.put("/fcm-token/{user_id}")
def update_fcm_token(user_id: int, payload: FcmTokenRequest, db: Session = Depends(get_db)):
    return UserController.update_fcm_token(db, user_id, payload.fcm_token)


@router.delete("/fcm-token/{user_id}")
def clear_fcm_token(user_id: int, db: Session = Depends(get_db)):
    """Efface le token FCM lors de la déconnexion pour éviter les notifications croisées."""
    return UserController.update_fcm_token(db, user_id, None)


@router.post("/test-notification/{user_id}")
def test_notification(user_id: int, db: Session = Depends(get_db)):
    return UserController.test_notification(db, user_id)