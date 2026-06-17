from sqlalchemy.orm import Session
from app.models.user import User
from app.models.base_enums import UserRoleEnum
from app.models.driver import Driver
from passlib.hash import bcrypt
from datetime import datetime, date

def get_user_by_email(db: Session, email: str):
    return db.query(User).filter(User.email == email).first()

def create_user(db: Session, full_name, email, phone, password, role,
                user_image=None, driver_image=None, license_number=None, license_expiry=None):
    hashed_password = bcrypt.hash(password)

    if role == UserRoleEnum.driver.value or role == UserRoleEnum.driver:
        if not license_number or not license_expiry or not driver_image:
            raise ValueError("Driver must have license and driver image")
            
        if isinstance(license_expiry, str):
            try:
                expiry_date = date.fromisoformat(license_expiry)
            except ValueError:
                raise ValueError("Format date license_expiry invalide (YYYY-MM-DD attendu)")
        else:
            expiry_date = license_expiry

        db_user = Driver(
            full_name=full_name,
            email=email,
            phone=phone,
            password_hash=hashed_password,
            role=role,
            is_active=True,
            created_at=datetime.now(),
            updated_at=datetime.now(),
            image_url=user_image,
            license_number=license_number,
            cin_card_photo=driver_image,
            driver_card_photo=driver_image,
            license_expiry_date=expiry_date,
            is_available=False,
            average_rating=5.0
        )
    else:
        db_user = User(
            full_name=full_name,
            email=email,
            phone=phone,
            password_hash=hashed_password,
            role=role,
            is_active=True,
            created_at=datetime.now(),
            updated_at=datetime.now(),
            image_url=user_image
        )

    db.add(db_user)
    db.commit()
    db.refresh(db_user)

    return db_user