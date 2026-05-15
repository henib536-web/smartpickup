from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from app.database.connection import get_db
from app.schemas.user import UserResponse
from app.controllers.admin_controller import AdminController
from app.models.user import User
from app.models.ride_request import RideRequest
from app.models.taxi import Taxi
from app.models.ride_assignment import RideAssignment
from app.models.base_enums import RideStatusEnum, AssignmentStatus, UserRoleEnum
from app.models.driver import Driver
from pydantic import BaseModel

router = APIRouter(prefix="/api/admin", tags=["Admin"])

class StatusUpdate(BaseModel):
    is_active: bool

class AssignTaxiRequest(BaseModel):
    taxi_id: int

@router.get("/stats")
def get_admin_stats(db: Session = Depends(get_db)):
    return AdminController.get_stats(db)

@router.get("/analytics")
def get_analytics(db: Session = Depends(get_db)):
    return AdminController.get_analytics(db)

@router.get("/drivers/pending", response_model=List[UserResponse])
def get_pending_drivers(db: Session = Depends(get_db)):
    return AdminController.get_pending_drivers(db)

@router.post("/drivers/{driver_id}/approve")
def approve_driver(driver_id: int, db: Session = Depends(get_db)):
    return AdminController.approve_driver(db, driver_id)

@router.get("/rides/recent")
def get_recent_rides(limit: int = 10, db: Session = Depends(get_db)):
    return AdminController.get_recent_rides(db, limit)

# New routes for React Admin
@router.get("/users")
def get_all_users(db: Session = Depends(get_db)):
    users = db.query(User).all()
    res = []
    for u in users:
        u_data = {
            "user_id": u.user_id,
            "full_name": u.full_name,
            "email": u.email,
            "phone": u.phone,
            "role": u.role.value if hasattr(u.role, 'value') else u.role,
            "is_active": u.is_active,
            "created_at": u.created_at,
            "image_url": u.image_url,
        }
        if u.role == UserRoleEnum.driver or u.role == 'driver':
            driver = db.query(Driver).filter(Driver.driver_id == u.user_id).first()
            if driver:
                u_data.update({
                    "license_number": driver.license_number,
                    "cin_card_photo": driver.cin_card_photo,
                    "driver_card_photo": driver.driver_card_photo,
                    "license_expiry_date": str(driver.license_expiry_date) if driver.license_expiry_date else None,
                    "average_rating": driver.average_rating,
                })
        res.append(u_data)
    return res

@router.put("/users/{user_id}/status")
def update_user_status(user_id: int, status: StatusUpdate, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.user_id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_active = status.is_active
    db.commit()
    return {"message": "Status updated"}

@router.delete("/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.user_id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    db.delete(user)
    db.commit()
    return {"message": "User deleted"}

@router.get("/rides")
def get_all_rides(db: Session = Depends(get_db)):
    return db.query(RideRequest).all()

@router.get("/taxis")
def get_all_taxis(db: Session = Depends(get_db)):
    return db.query(Taxi).all()

@router.post("/rides/{request_id}/assign")
def assign_ride(request_id: int, payload: AssignTaxiRequest, db: Session = Depends(get_db)):
    ride = db.query(RideRequest).filter(RideRequest.request_id == request_id).first()
    if not ride:
         raise HTTPException(status_code=404, detail="Ride request not found")
         
    ride.status = RideStatusEnum.ACCEPTED
    
    assignment = RideAssignment(request_id=request_id, taxi_id=payload.taxi_id, status=AssignmentStatus.PENDING)
    db.add(assignment)
    db.commit()
    return {"message": "Ride assigned"}
