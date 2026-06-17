from app.database.connection import SessionLocal
from app.models.driver import Driver
from app.models.user import User

db = SessionLocal()
try:
    drivers = db.query(Driver).all()
    print(f"Total drivers in database: {len(drivers)}")
    for d in drivers:
        print(f"Driver ID: {d.driver_id}, Name: {d.full_name}, Email: {d.email}")
        print(f"  License: {d.license_number}")
        print(f"  CIN Photo: {d.cin_card_photo}")
        print(f"  Driver Card Photo: {d.driver_card_photo}")
        print(f"  Is Active: {d.is_active}")
        print("-" * 50)
finally:
    db.close()
