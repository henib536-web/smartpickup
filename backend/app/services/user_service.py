from sqlalchemy.orm import Session
from app.models.user import User, UserRoleEnum
from app.models.driver_profile import DriverProfile
from passlib.hash import bcrypt
from datetime import datetime
def get_user_by_email(db: Session, email: str):
    return db.query(User).filter(User.email == email).first()
def create_user(db: Session, full_name, email, phone, password, role,
                user_image=None, driver_image=None, license_number=None, license_expiry=None):
    hashed_password = bcrypt.hash(password)

    # Créer l'utilisateur
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

    # Si driver, créer aussi son profile
    if role == UserRoleEnum.driver.value:
        if not license_number or not license_expiry or not driver_image:
            raise ValueError("Driver must have license and driver image")
        db_driver = DriverProfile(
            driver_id=db_user.user_id,
            license_number=license_number,
            license_expiry=license_expiry,
            total_trips=0,
            average_rating=0.0,
            image_url=driver_image
        )
        db.add(db_driver)
        db.commit()

    return db_user