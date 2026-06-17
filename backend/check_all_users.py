from app.database.connection import SessionLocal
from app.models.user import User
from app.models.base_enums import UserRoleEnum

db = SessionLocal()
try:
    all_users = db.query(User).all()
    print(f"Total users in database: {len(all_users)}")
    for u in all_users:
        print(f"User ID: {u.user_id}, Name: {u.full_name}, Email: {u.email}, Role: {u.role}, RoleType: {type(u.role)}")
        
    filtered = db.query(User).filter(User.role != UserRoleEnum.admin).all()
    print(f"Filtered (role != admin) users: {len(filtered)}")
    for u in filtered:
        print(f"  User ID: {u.user_id}, Name: {u.full_name}, Role: {u.role}")
finally:
    db.close()
