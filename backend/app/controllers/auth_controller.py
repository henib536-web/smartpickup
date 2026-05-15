from fastapi import HTTPException, status, UploadFile
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from jose import JWTError, jwt
from typing import Optional
from app.models.user import User
from app.models.base_enums import UserRoleEnum
from app.models.client import Client
from app.models.driver import Driver
from app.models.passenger import Passenger
from app.models.email_verification import EmailVerificationCode
from app.services.auth_service import (
    verify_password,
    get_password_hash,
    create_access_token,
    save_upload_file,
    _normalize_email,
    _random_six_digit_code,
    _verify_code_or_raise,
    ACCESS_TOKEN_EXPIRE_MINUTES
)
from app.services.email_service import (
    hash_verification_code,
    send_signup_code_email,
    send_password_reset_code_email,
)
from datetime import date

class AuthController:
    @staticmethod
    def send_signup_code(db: Session, email: str):
        existing_user = db.query(User).filter(User.email == email).first()
        if existing_user:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cet email est déjà enregistré.")
        
        email_n = _normalize_email(email)
        db.query(EmailVerificationCode).filter(EmailVerificationCode.email == email_n, EmailVerificationCode.purpose == "signup").delete()
        
        code = _random_six_digit_code()
        row = EmailVerificationCode(
            email=email_n,
            code_hash=hash_verification_code(email, code),
            purpose="signup",
            expires_at=datetime.utcnow() + timedelta(minutes=15),
            used=False,
        )
        db.add(row)
        db.commit()
        
        try:
            send_signup_code_email(email, code)
        except Exception as e:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Envoi de l'email impossible: {str(e)}")
        
        return {"message": "Code envoyé par email."}

    @staticmethod
    def forgot_password(db: Session, email: str):
        user = db.query(User).filter(User.email == email).first()
        if not user:
            return {"message": "Si cet email est enregistré, un code vous a été envoyé."}
        
        email_n = _normalize_email(email)
        db.query(EmailVerificationCode).filter(EmailVerificationCode.email == email_n, EmailVerificationCode.purpose == "password_reset").delete()
        
        code = _random_six_digit_code()
        row = EmailVerificationCode(
            email=email_n,
            code_hash=hash_verification_code(email, code),
            purpose="password_reset",
            expires_at=datetime.utcnow() + timedelta(minutes=15),
            used=False,
        )
        db.add(row)
        db.commit()
        
        try:
            send_password_reset_code_email(email, code)
        except Exception as e:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Envoi de l'email impossible: {str(e)}")
        
        return {"message": "Si cet email est enregistré, un code vous a été envoyé."}

    @staticmethod
    def reset_password(db: Session, payload):
        user = db.query(User).filter(User.email == payload.email).first()
        if not user:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Code invalide ou expiré.")
        
        try:
            _verify_code_or_raise(db, str(payload.email), payload.code, "password_reset")
            user.password_hash = get_password_hash(payload.new_password)
            user.updated_at = datetime.utcnow()
            db.commit()
        except HTTPException:
            db.rollback()
            raise
        return {"message": "Mot de passe mis à jour."}

    @staticmethod
    def signup(db: Session, full_name, email, phone, password, verification_code, role, license_number, license_expiry, profile_image, cin_image, driver_card_image):
        existing_user = db.query(User).filter(User.email == email).first()
        if existing_user:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cet email est déjà enregistré.")

        try:
            role_enum = UserRoleEnum(role.lower().strip())
        except ValueError:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Rôle invalide: '{role}'.")

        if role_enum == UserRoleEnum.driver:
            if not license_number or not license_expiry:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Le chauffeur doit fournir le numero de permis et sa date d'expiration.")
            if not cin_image or not driver_card_image:
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Le chauffeur doit fournir la carte CIN et les documents chauffeur.")

        _verify_code_or_raise(db, str(email), verification_code, "signup")

        profile_image_url = save_upload_file(profile_image)
        cin_image_url = save_upload_file(cin_image)
        driver_card_image_url = save_upload_file(driver_card_image)

        now = datetime.utcnow()
        user_params = {
            "full_name": full_name,
            "email": str(email),
            "phone": phone,
            "password_hash": get_password_hash(password),
            "role": role_enum,
            "is_active": False,
            "created_at": now,
            "updated_at": now,
            "image_url": profile_image_url,
            "fcm_token": None
        }

        try:
            if role_enum == UserRoleEnum.driver:
                expiry_date = date.fromisoformat(license_expiry)
                new_user = Driver(**user_params, license_number=license_number, cin_card_photo=cin_image_url, license_expiry_date=expiry_date, driver_card_photo=driver_card_image_url, is_available=True, average_rating=5.0)
            elif role_enum == UserRoleEnum.commuter:
                new_user = Client(**user_params)
            else:
                new_user = User(**user_params)

            db.add(new_user)
            db.flush()

            if role_enum == UserRoleEnum.commuter:
                db.add(Passenger(passenger_id=new_user.user_id, full_name=full_name, type="adult"))

            db.commit()
            db.refresh(new_user)
            return {
                "user_id": new_user.user_id,
                "full_name": new_user.full_name,
                "email": new_user.email,
                "role": new_user.role.value,
                "image_url": new_user.image_url,
            }
        except Exception as e:
            db.rollback()
            raise HTTPException(status_code=500, detail=f"Erreur lors de la création : {str(e)}")

    @staticmethod
    def login(db: Session, login_data):
        user = db.query(User).filter(User.email == login_data.email).first()
        if not user or not verify_password(login_data.password, user.password_hash):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Email ou mot de passe incorrect")
        
        if not user.is_active:
            raise HTTPException(status_code=403, detail="Compte désactivé")
        
        expires_delta = timedelta(days=7) if login_data.remember_me else timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = create_access_token(data={"sub": user.email, "user_id": user.user_id, "role": user.role.value}, expires_delta=expires_delta)
        
        return {
            "access_token": access_token,
            "token_type": "bearer",
            "user_id": user.user_id,
            "email": user.email,
            "full_name": user.full_name,
            "role": user.role.value,
            "expires_in": int(expires_delta.total_seconds())
        }

    @staticmethod
    def get_me(db: Session, email: str):
        user = db.query(User).filter(User.email == email).first()
        if user is None:
            raise HTTPException(status_code=404, detail="Utilisateur non trouvé")
        return {"id": user.user_id, "email": user.email, "full_name": user.full_name, "role": user.role.value}
