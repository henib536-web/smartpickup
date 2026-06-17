from fastapi import APIRouter, Depends, HTTPException, status, Form
from sqlalchemy.orm import Session
from typing import List, Optional
from app.database.connection import get_db
from app.schemas.user import UserResponse
from app.controllers.admin_controller import AdminController
from app.models.user import User
from app.models.ride_request import RideRequest
from app.models.taxi import Taxi
from app.models.recurring_schedule import RecurringSchedule
from app.models.ride_assignment import RideAssignment
from app.models.base_enums import RideStatusEnum, AssignmentStatus, UserRoleEnum
from app.models.driver import Driver
from app.models.incident_rapport import IncidentReport
from app.models.ride_log import RideLog
from app.models.notification import NotificationModel
from app.services.notification_service import send_push_notification
from datetime import datetime
from pydantic import BaseModel

router = APIRouter(prefix="/api/admin", tags=["Admin"])

class CreateRidePayload(BaseModel):
    scheduled_for: datetime
    taxi_id: int

class ReportStatusUpdate(BaseModel):
    status: str
    resolution_note: Optional[str] = None

class UserUpdatePayload(BaseModel):
    full_name: str
    email: str
    phone: str
    license_number: Optional[str] = None
    average_rating: Optional[float] = None

class RatingUpdatePayload(BaseModel):
    average_rating: float

class AssignTaxiRequest(BaseModel):
    taxi_id: int

class StatusUpdate(BaseModel):
    is_active: bool

class PasswordResetPayload(BaseModel):
    new_password: str

from fastapi import UploadFile, File
import os
import shutil

@router.get("/stats")
def get_admin_stats(db: Session = Depends(get_db)):
    return AdminController.get_stats(db)

@router.get("/analytics")
def get_analytics(db: Session = Depends(get_db)):
    return AdminController.get_analytics(db)

@router.get("/drivers/pending", response_model=List[UserResponse])
def get_pending_drivers(db: Session = Depends(get_db)):
    return AdminController.get_pending_drivers(db)

@router.post("/drivers", status_code=status.HTTP_201_CREATED)
def create_driver_admin(
    full_name: str = Form(...),
    email: str = Form(...),
    phone: str = Form(...),
    password: str = Form(...),
    license_number: str = Form(...),
    license_expiry: str = Form(...),
    profile_image: Optional[UploadFile] = File(None),
    cin_image: UploadFile = File(...),
    driver_card_image: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    from app.services.auth_service import get_password_hash, save_upload_file
    
    existing = db.query(User).filter(User.email == email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    profile_url = save_upload_file(profile_image) if profile_image else None
    cin_url = save_upload_file(cin_image)
    driver_card_url = save_upload_file(driver_card_image)

    now = datetime.utcnow()
    from datetime import date
    try:
        expiry_date = date.fromisoformat(license_expiry)
    except ValueError:
        raise HTTPException(status_code=400, detail="Format date license_expiry invalide (YYYY-MM-DD attendu)")

    new_driver = Driver(
        full_name=full_name,
        email=email,
        phone=phone,
        password_hash=get_password_hash(password),
        role=UserRoleEnum.driver,
        is_active=True,  # Admin creates validated drivers directly
        created_at=now,
        updated_at=now,
        image_url=profile_url,
        license_number=license_number,
        cin_card_photo=cin_url,
        license_expiry_date=expiry_date,
        driver_card_photo=driver_card_url,
        is_available=False,
        average_rating=5.0
    )
    db.add(new_driver)
    db.commit()
    db.refresh(new_driver)
    
    return {"message": "Driver created successfully", "user_id": new_driver.user_id}

@router.post("/drivers/{driver_id}/approve")
def approve_driver(driver_id: int, db: Session = Depends(get_db)):
    return AdminController.approve_driver(db, driver_id)

@router.get("/rides/recent")
def get_recent_rides(limit: int = 10, db: Session = Depends(get_db)):
    return AdminController.get_recent_rides(db, limit)

# New routes for React Admin
@router.get("/users")
def get_all_users(db: Session = Depends(get_db)):
    users = db.query(User).filter(User.role != UserRoleEnum.admin).all()
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
                taxi = db.query(Taxi).filter(Taxi.driver_id == u.user_id).first()
                total_trips = 0
                if taxi:
                    total_trips = db.query(RideAssignment).filter(
                        RideAssignment.taxi_id == taxi.taxi_id,
                        RideAssignment.status == AssignmentStatus.ACCEPTED
                    ).count()
                u_data.update({
                    "license_number": driver.license_number,
                    "cin_card_photo": driver.cin_card_photo,
                    "driver_card_photo": driver.driver_card_photo,
                    "license_expiry_date": str(driver.license_expiry_date) if driver.license_expiry_date else None,
                    "average_rating": driver.average_rating,
                    "total_trips": total_trips,
                })
        res.append(u_data)
    return res

@router.get("/users/{user_id}/rides")
def get_user_rides(user_id: int, db: Session = Depends(get_db)):
    """Get all ride requests made by a client (commuter)"""
    from app.models.passenger import Passenger
    rides = db.query(RideRequest).filter(RideRequest.client_id == user_id).order_by(RideRequest.requested_at.desc()).all()
    result = []
    for ride in rides:
        # Find assigned driver
        assignment = db.query(RideAssignment).filter(
            RideAssignment.request_id == ride.request_id,
            RideAssignment.status == AssignmentStatus.ACCEPTED
        ).first()
        driver_name = None
        if assignment:
            taxi = db.query(Taxi).filter(Taxi.taxi_id == assignment.taxi_id).first()
            if taxi:
                d_user = db.query(User).filter(User.user_id == taxi.driver_id).first()
                if d_user:
                    driver_name = d_user.full_name
        
        # Load ride log details
        log = db.query(RideLog).filter(RideLog.ride_id == ride.request_id).first()
        amount_paid = log.amount_paid_cash if log else (ride.estimated_price / 1000 if ride.estimated_price else 0.0)
        distance = log.ride_distance if (log and log.ride_distance) else (float(ride.distance_km) if ride.distance_km else 0.0)
        
        duration = None
        if log and log.start_time and log.end_time:
            diff = log.end_time - log.start_time
            duration_mins = int(diff.total_seconds() / 60)
            duration = f"{duration_mins} min"
        elif log and log.start_time:
            duration = "En cours"
            
        result.append({
            "request_id": ride.request_id,
            "ref": f"REF-{str(ride.request_id).zfill(4)}",
            "status": ride.status.value if hasattr(ride.status, 'value') else str(ride.status),
            "pickup_location": ride.pickup_location,
            "dropoff_location": ride.dropoff_location,
            "scheduled_for": ride.scheduled_for.isoformat() if ride.scheduled_for else None,
            "requested_at": ride.requested_at.isoformat() if ride.requested_at else None,
            "driver_name": driver_name,
            "cancellation_reason": ride.cancellation_reason,
            "cancelled_by": ride.cancelled_by.value if ride.cancelled_by and hasattr(ride.cancelled_by, 'value') else str(ride.cancelled_by) if ride.cancelled_by else None,
            "amount_paid": amount_paid,
            "distance": distance,
            "duration": duration,
        })
    return result

@router.get("/users/{user_id}/driver-rides")
def get_driver_rides(user_id: int, db: Session = Depends(get_db)):
    """Get all rides for a driver: completed ones and active/accepted ones not yet arrived"""
    taxi = db.query(Taxi).filter(Taxi.driver_id == user_id).first()
    if not taxi:
        return {"completed": [], "active": []}
    
    assignments = db.query(RideAssignment).filter(
        RideAssignment.taxi_id == taxi.taxi_id,
        RideAssignment.status == AssignmentStatus.ACCEPTED
    ).all()
    request_ids = [a.request_id for a in assignments]
    
    rides = db.query(RideRequest).filter(RideRequest.request_id.in_(request_ids)).order_by(RideRequest.scheduled_for.desc()).all()
    
    completed = []
    active = []
    
    for ride in rides:
        status_str = ride.status.value if hasattr(ride.status, 'value') else str(ride.status)
        # Find passenger
        passenger_name = "Inconnu"
        from app.models.passenger import Passenger
        if ride.passenger_id:
            p = db.query(Passenger).filter(Passenger.passenger_id == ride.passenger_id).first()
            if p:
                passenger_name = p.full_name
        
        # Load ride log details
        log = db.query(RideLog).filter(RideLog.ride_id == ride.request_id).first()
        amount_paid = log.amount_paid_cash if log else (ride.estimated_price / 1000 if ride.estimated_price else 0.0)
        distance = log.ride_distance if (log and log.ride_distance) else (float(ride.distance_km) if ride.distance_km else 0.0)
        
        duration = None
        if log and log.start_time and log.end_time:
            diff = log.end_time - log.start_time
            duration_mins = int(diff.total_seconds() / 60)
            duration = f"{duration_mins} min"
        elif log and log.start_time:
            duration = "En cours"
            
        ride_data = {
            "request_id": ride.request_id,
            "ref": f"REF-{str(ride.request_id).zfill(4)}",
            "status": status_str,
            "pickup_location": ride.pickup_location,
            "dropoff_location": ride.dropoff_location,
            "scheduled_for": ride.scheduled_for.isoformat() if ride.scheduled_for else None,
            "requested_at": ride.requested_at.isoformat() if ride.requested_at else None,
            "passenger_name": passenger_name,
            "amount_paid": amount_paid,
            "distance": distance,
            "duration": duration,
        }
        
        if status_str == "COMPLETED":
            completed.append(ride_data)
        else:
            active.append(ride_data)
            
    return {"completed": completed, "active": active}

@router.get("/users/{user_id}/reports")
def get_user_reports(user_id: int, db: Session = Depends(get_db)):
    """Get all incident reports involving a user (either as client or driver)"""
    reports = db.query(IncidentReport).order_by(IncidentReport.report_id.desc()).all()
    res = []
    for r in reports:
        ride = db.query(RideRequest).filter(RideRequest.request_id == r.ride_id).first()
        if not ride:
            continue
        
        # Check driver
        driver_id = None
        assignment = db.query(RideAssignment).filter(
            RideAssignment.request_id == r.ride_id,
            RideAssignment.status == AssignmentStatus.ACCEPTED
        ).first()
        if assignment:
            taxi = db.query(Taxi).filter(Taxi.taxi_id == assignment.taxi_id).first()
            if taxi:
                driver_id = taxi.driver_id
        
        if ride.client_id == user_id or driver_id == user_id:
            reporter_name = "Utilisateur"
            user = db.query(User).filter(User.user_id == ride.client_id).first()
            if user:
                reporter_name = user.full_name
            
            driver_info = None
            if driver_id:
                d_user = db.query(User).filter(User.user_id == driver_id).first()
                driver = db.query(Driver).filter(Driver.driver_id == driver_id).first()
                if d_user and driver:
                    driver_info = {
                        "driver_id": driver_id,
                        "name": d_user.full_name,
                        "average_rating": driver.average_rating
                    }
                    
            res.append({
                "report_id": r.report_id,
                "ride_id": r.ride_id,
                "report_type": r.report_type,
                "severity_level": r.severity_level,
                "description": r.description,
                "status": r.status.lower() if r.status else "open",
                "reporter_name": reporter_name,
                "created_at": r.created_at.isoformat() if r.created_at else datetime.utcnow().isoformat(),
                "resolution_note": r.resolution_note,
                "driver": driver_info
            })
    return res



@router.get("/users/{user_id}")
def get_user_details(user_id: int, db: Session = Depends(get_db)):
    u = db.query(User).filter(User.user_id == user_id).first()
    if not u:
        raise HTTPException(status_code=404, detail="User not found")
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
            taxi = db.query(Taxi).filter(Taxi.driver_id == u.user_id).first()
            total_trips = 0
            if taxi:
                total_trips = db.query(RideAssignment).filter(
                    RideAssignment.taxi_id == taxi.taxi_id,
                    RideAssignment.status == AssignmentStatus.ACCEPTED
                ).count()
            u_data.update({
                "license_number": driver.license_number,
                "cin_card_photo": driver.cin_card_photo,
                "driver_card_photo": driver.driver_card_photo,
                "license_expiry_date": str(driver.license_expiry_date) if driver.license_expiry_date else None,
                "average_rating": driver.average_rating,
                "total_trips": total_trips,
            })
    return u_data

@router.put("/users/{user_id}/status")
def update_user_status(user_id: int, status: StatusUpdate, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.user_id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_active = status.is_active
    db.commit()
    return {"message": "Status updated"}


@router.put("/users/{user_id}")
def update_user_details(user_id: int, payload: UserUpdatePayload, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.user_id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.full_name = payload.full_name
    user.email = payload.email
    user.phone = payload.phone
    
    if user.role == UserRoleEnum.driver or user.role == 'driver':
        driver = db.query(Driver).filter(Driver.driver_id == user_id).first()
        if driver:
            driver.license_number = payload.license_number
            if payload.average_rating is not None:
                driver.average_rating = payload.average_rating
            
    db.commit()
    return {"message": "User updated successfully"}

from app.services.auth_service import get_password_hash

@router.put("/users/{user_id}/password")
def reset_user_password(user_id: int, payload: PasswordResetPayload, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.user_id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.password_hash = get_password_hash(payload.new_password)
    db.commit()
    return {"message": "Password reset successfully"}

@router.post("/users/{user_id}/photo")
def upload_user_photo(user_id: int, file: UploadFile = File(...), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.user_id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
        
    uploads_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "uploads"))
    os.makedirs(uploads_dir, exist_ok=True)
    
    file_extension = os.path.splitext(file.filename)[1]
    file_name = f"user_{user_id}_{datetime.now().strftime('%Y%m%d%H%M%S')}{file_extension}"
    file_path = os.path.join(uploads_dir, file_name)
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
        
    user.image_url = f"/uploads/{file_name}"
    db.commit()
    
    return {"message": "Photo uploaded successfully", "image_url": user.image_url}

class TaxiUpdatePayload(BaseModel):
    plate_number: Optional[str] = None
    vehicle_model: Optional[str] = None

@router.put("/drivers/{driver_id}/taxi")
def update_driver_taxi(driver_id: int, payload: TaxiUpdatePayload, db: Session = Depends(get_db)):
    taxi = db.query(Taxi).filter(Taxi.driver_id == driver_id).first()
    if not taxi:
        raise HTTPException(status_code=404, detail="Taxi not found for this driver")
    if payload.plate_number is not None:
        taxi.plate_number = payload.plate_number
    if payload.vehicle_model is not None:
        taxi.vehicle_model = payload.vehicle_model
    db.commit()
    return {"message": "Taxi updated successfully"}

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
    from app.models.passenger import Passenger
    rides = db.query(RideRequest).order_by(RideRequest.requested_at.desc()).all()
    result = []
    for ride in rides:
        # Get client (user who booked) name
        client_name = None
        if ride.client_id:
            client_user = db.query(User).filter(User.user_id == ride.client_id).first()
            if client_user:
                client_name = client_user.full_name

        # Get passenger name (may differ from client if booked for someone else)
        passenger_name = None
        if ride.passenger_id:
            p = db.query(Passenger).filter(Passenger.passenger_id == ride.passenger_id).first()
            if p:
                passenger_name = p.full_name

        # Get assigned driver if any
        driver_name = None
        assignment = db.query(RideAssignment).filter(
            RideAssignment.request_id == ride.request_id,
            RideAssignment.status == AssignmentStatus.ACCEPTED
        ).first()
        if assignment:
            taxi = db.query(Taxi).filter(Taxi.taxi_id == assignment.taxi_id).first()
            if taxi:
                d_user = db.query(User).filter(User.user_id == taxi.driver_id).first()
                if d_user:
                    driver_name = d_user.full_name

        result.append({
            "request_id": ride.request_id,
            "client_id": ride.client_id,
            "client_name": client_name,
            "passenger_id": ride.passenger_id,
            "passenger_name": passenger_name,
            "pickup_location": ride.pickup_location,
            "dropoff_location": ride.dropoff_location,
            "status": ride.status.value if hasattr(ride.status, 'value') else str(ride.status),
            "requested_at": ride.requested_at.isoformat() if ride.requested_at else None,
            "created_at": ride.requested_at.isoformat() if ride.requested_at else None,
            "estimated_distance": float(ride.distance_km) if ride.distance_km else None,
            "estimated_duration": ride.estimated_duration if hasattr(ride, 'estimated_duration') else None,
            "estimated_price": ride.estimated_price,
            "driver_name": driver_name,
            "schedule_id": ride.schedule_id,
        })
    return result

@router.get("/recurring-rides")
def get_all_recurring_rides(db: Session = Depends(get_db)):
    """Return all recurring schedules with estimated price and total period cost"""
    from app.models.recurring_schedule import RecurringSchedule
    from datetime import timedelta, date

    def count_occurrences(start, end, day_enum):
        day_name = day_enum.value if hasattr(day_enum, 'value') else str(day_enum)
        weekday_map = {
            "MONDAY": 0, "TUESDAY": 1, "WEDNESDAY": 2,
            "THURSDAY": 3, "FRIDAY": 4, "SATURDAY": 5, "SUNDAY": 6,
        }
        target = weekday_map.get(day_name.upper(), -1)
        if target < 0:
            return 0
        count = 0
        d = start
        while d <= end:
            if d.weekday() == target:
                count += 1
            d += timedelta(days=1)
        return count

    schedules = db.query(RecurringSchedule).order_by(RecurringSchedule.schedule_id.desc()).all()
    result = []

    for s in schedules:
        client_user = db.query(User).filter(User.user_id == s.client_id).first()
        client_name = client_user.full_name if client_user else f"Client #{s.client_id}"
        day_label = s.day_of_week.value if s.day_of_week and hasattr(s.day_of_week, 'value') else str(s.day_of_week or "")
        price_per_ride_dt = round(s.estimated_price / 1000, 2) if s.estimated_price else None
        nb_occurrences = count_occurrences(s.start_date, s.end_date, s.day_of_week) if (s.start_date and s.end_date) else None
        total_price_dt = round(price_per_ride_dt * nb_occurrences, 2) if (price_per_ride_dt and nb_occurrences) else None

        result.append({
            "schedule_id": s.schedule_id,
            "client_id": s.client_id,
            "client_name": client_name,
            "pickup_location": s.pickup_location,
            "dropoff_location": s.dropoff_location,
            "day_of_week": day_label,
            "start_date": s.start_date.isoformat() if s.start_date else None,
            "end_date": s.end_date.isoformat() if s.end_date else None,
            "pickup_time": s.pickup_time.strftime("%H:%M") if s.pickup_time else None,
            "is_active": s.is_active,
            "distance_km": float(s.distance_km) if s.distance_km else None,
            "estimated_price_per_ride": price_per_ride_dt,
            "nb_occurrences": nb_occurrences,
            "total_period_price": total_price_dt,
        })
    return result

def generate_missing_rides_for_schedule(schedule_id: int, db: Session):
    from app.models.recurring_schedule import RecurringSchedule
    from datetime import timedelta, datetime
    schedule = db.query(RecurringSchedule).filter(RecurringSchedule.schedule_id == schedule_id).first()
    if not schedule or not schedule.start_date or not schedule.end_date:
        return
        
    weekday_map = {
        "MONDAY": 0, "TUESDAY": 1, "WEDNESDAY": 2,
        "THURSDAY": 3, "FRIDAY": 4, "SATURDAY": 5, "SUNDAY": 6,
    }
    day_name = schedule.day_of_week.value if hasattr(schedule.day_of_week, 'value') else str(schedule.day_of_week)
    target_weekday = weekday_map.get(day_name.upper())
    if target_weekday is None:
        return

    existing_rides = db.query(RideRequest).filter(RideRequest.schedule_id == schedule_id).all()
    existing_dates = set(r.scheduled_for.date() for r in existing_rides if r.scheduled_for)

    current_date = schedule.start_date
    while current_date <= schedule.end_date:
        if current_date.weekday() == target_weekday:
            if current_date not in existing_dates:
                pickup_dt = datetime.combine(current_date, schedule.pickup_time) if schedule.pickup_time else datetime.combine(current_date, datetime.min.time())
                new_ride = RideRequest(
                    client_id=schedule.client_id,
                    passenger_id=None,
                    pickup_location=schedule.pickup_location,
                    dropoff_location=schedule.dropoff_location,
                    scheduled_for=pickup_dt,
                    distance_km=schedule.distance_km,
                    estimated_price=schedule.estimated_price,
                    status=RideStatusEnum.PENDING,
                    schedule_id=schedule.schedule_id,
                    requested_at=datetime.utcnow(),
                )
                db.add(new_ride)
        current_date += timedelta(days=1)
    db.commit()

@router.get("/recurring-rides/{schedule_id}/rides")
def get_rides_for_schedule(schedule_id: int, db: Session = Depends(get_db)):
    """Return all ride_requests linked to a recurring schedule, with driver info"""
    generate_missing_rides_for_schedule(schedule_id, db)
    
    from app.models.passenger import Passenger
    rides = (
        db.query(RideRequest)
        .filter(RideRequest.schedule_id == schedule_id)
        .order_by(RideRequest.scheduled_for.asc())
        .all()
    )
    result = []
    for ride in rides:
        # Client name
        client_name = None
        if ride.client_id:
            cu = db.query(User).filter(User.user_id == ride.client_id).first()
            if cu:
                client_name = cu.full_name

        # Passenger name
        passenger_name = None
        if ride.passenger_id:
            p = db.query(Passenger).filter(Passenger.passenger_id == ride.passenger_id).first()
            if p:
                passenger_name = p.full_name

        # Assigned driver
        driver_name = None
        plate_number = None
        assignment = db.query(RideAssignment).filter(
            RideAssignment.request_id == ride.request_id,
            RideAssignment.status == AssignmentStatus.ACCEPTED
        ).first()
        if assignment:
            taxi = db.query(Taxi).filter(Taxi.taxi_id == assignment.taxi_id).first()
            if taxi:
                plate_number = taxi.plate_number
                d_user = db.query(User).filter(User.user_id == taxi.driver_id).first()
                if d_user:
                    driver_name = d_user.full_name

        result.append({
            "request_id": ride.request_id,
            "client_name": client_name,
            "passenger_name": passenger_name,
            "pickup_location": ride.pickup_location,
            "dropoff_location": ride.dropoff_location,
            "scheduled_for": ride.scheduled_for.isoformat() if ride.scheduled_for else None,
            "requested_at": ride.requested_at.isoformat() if ride.requested_at else None,
            "status": ride.status.value if hasattr(ride.status, 'value') else str(ride.status),
            "estimated_price": ride.estimated_price,
            "distance_km": float(ride.distance_km) if ride.distance_km else None,
            "driver_name": driver_name,
            "plate_number": plate_number,
        })
    return result

# -----------------------------------------------------------------------------
# Create a single ride for a recurring schedule and assign a driver in one step
# -----------------------------------------------------------------------------
@router.post("/recurring-rides/{schedule_id}/create-ride")
def create_ride_for_schedule(
    schedule_id: int,
    payload: CreateRidePayload,
    db: Session = Depends(get_db)
):
    """Create a ride request linked to a recurring schedule and assign a taxi.

    Expected JSON payload:
        {
            "scheduled_for": "2026-07-01T14:30:00",  # ISO 8601 datetime string
            "taxi_id": 12
        }
    """
    from app.models.ride_request import RideRequest
    from app.models.ride_assignment import RideAssignment, AssignmentStatus
    from app.models.taxi import Taxi
    from app.models.user import User
    from datetime import datetime

    # Validate schedule existence
    schedule = db.query(RecurringSchedule).filter(RecurringSchedule.schedule_id == schedule_id).first()
    if not schedule:
        raise HTTPException(status_code=404, detail="Planning non trouvé")

    # Parse datetime
    try:
        scheduled_dt = payload.scheduled_for
    except Exception:
        raise HTTPException(status_code=400, detail="Format datetime invalide")

    taxi_id = payload.taxi_id
    if not taxi_id:
        raise HTTPException(status_code=400, detail="taxi_id requis")

    # Verify taxi exists
    taxi = db.query(Taxi).filter(Taxi.taxi_id == taxi_id).first()
    if not taxi:
        raise HTTPException(status_code=404, detail="Taxi non trouvé")

    # Create the RideRequest (copie des champs du planning)
    ride = RideRequest(
        client_id=schedule.client_id,
        passenger_id=None,
        pickup_location=schedule.pickup_location,
        dropoff_location=schedule.dropoff_location,
        scheduled_for=scheduled_dt,
        distance_km=schedule.distance_km,
        estimated_price=schedule.estimated_price,
        status=RideStatusEnum.PENDING,
        schedule_id=schedule.schedule_id,
        requested_at=datetime.utcnow(),
    )
    db.add(ride)
    db.flush()  # obtain ride.request_id

    # Création de l'assignation
    assignment = RideAssignment(
        request_id=ride.request_id,
        taxi_id=taxi.taxi_id,
        status=AssignmentStatus.ACCEPTED,
    )
    db.add(assignment)
    db.commit()

    return {
        "request_id": ride.request_id,
        "scheduled_for": ride.scheduled_for.isoformat(),
        "taxi_id": taxi.taxi_id,
        "driver_name": db.query(User).filter(User.user_id == taxi.driver_id).first().full_name if taxi.driver_id else None,
        "plate_number": taxi.plate_number,
    }

@router.get("/taxis")
def get_all_taxis(db: Session = Depends(get_db)):
    from app.controllers.driver_controller import DriverController
    DriverController.auto_offline_stale_drivers(db)
    
    drivers = db.query(Driver).all()
    res = []
    for d in drivers:
        taxi = db.query(Taxi).filter(Taxi.driver_id == d.driver_id).first()
        if not taxi:
            # Create a default Taxi record so the driver can be assigned rides
            taxi = Taxi(
                driver_id=d.driver_id,
                plate_number=f"À définir - {d.driver_id}",
                vehicle_model="À définir",
                availability=d.is_available
            )
            db.add(taxi)
            db.commit()
            db.refresh(taxi)
            
        driver_user = db.query(User).filter(User.user_id == d.driver_id).first()
        res.append({
            "taxi_id": taxi.taxi_id,
            "driver_id": d.driver_id,
            "plate_number": taxi.plate_number,
            "vehicle_model": taxi.vehicle_model,
            "availability": taxi.availability,
            "driver_name": driver_user.full_name if driver_user else f"Driver #{d.driver_id}",
            "is_online": d.is_available
        })
    return res

@router.post("/rides/{request_id}/assign")
def assign_ride(request_id: int, payload: AssignTaxiRequest, db: Session = Depends(get_db)):
    ride = db.query(RideRequest).filter(RideRequest.request_id == request_id).first()
    if not ride:
         raise HTTPException(status_code=404, detail="Ride request not found")
         
    taxi = db.query(Taxi).filter(Taxi.taxi_id == payload.taxi_id).first()
    if not taxi:
         raise HTTPException(status_code=404, detail="Taxi not found")
         
    ride.status = RideStatusEnum.ACCEPTED
    
    # Create accepted assignment
    assignment = RideAssignment(
        request_id=request_id, 
        taxi_id=payload.taxi_id, 
        status=AssignmentStatus.ACCEPTED,
        responded_at=datetime.utcnow()
    )
    db.add(assignment)
    
    # Create ride log
    new_log = RideLog(ride_id=request_id, amount_suggested=15.0, is_payment_confirmed=False)
    db.add(new_log)
    
    # Notify commuter
    client_title = "✅ Course Assignée"
    client_body = f"L'administrateur a assigné un chauffeur pour votre course de {ride.pickup_location}."
    db.add(NotificationModel(
        user_id=ride.client_id,
        title=client_title,
        message=client_body,
        type="ride_accepted",
        is_read=False,
        created_at=datetime.utcnow()
    ))
    client_user = db.query(User).filter(User.user_id == ride.client_id).first()
    if client_user and client_user.fcm_token:
        try:
            send_push_notification(client_user.fcm_token, client_title, client_body, {"type": "ride_accepted", "request_id": str(ride.request_id)})
        except Exception as e:
            print(f"Error sending client FCM notification: {e}")

    # Notify driver
    driver_title = "🚕 Course Assignée"
    driver_body = f"L'administrateur vous a assigné la course de {ride.pickup_location}."
    db.add(NotificationModel(
        user_id=taxi.driver_id,
        title=driver_title,
        message=driver_body,
        type="ride_accepted_driver",
        is_read=False,
        created_at=datetime.utcnow()
    ))
    driver_user = db.query(User).filter(User.user_id == taxi.driver_id).first()
    if driver_user and driver_user.fcm_token:
        try:
            send_push_notification(driver_user.fcm_token, driver_title, driver_body, {"type": "ride_accepted_driver", "request_id": str(ride.request_id)})
        except Exception as e:
            print(f"Error sending driver FCM notification: {e}")

    db.commit()
    return {"message": "Ride assigned"}

@router.get("/reports")
def get_all_reports(db: Session = Depends(get_db)):
    reports = db.query(IncidentReport).order_by(IncidentReport.report_id.desc()).all()
    res = []
    for r in reports:
        reporter_name = "Utilisateur"
        driver_info = None
        ride_details = None
        
        ride = db.query(RideRequest).filter(RideRequest.request_id == r.ride_id).first()
        if ride:
            user = db.query(User).filter(User.user_id == ride.client_id).first()
            if user:
                reporter_name = user.full_name
            
            # Build ride details
            ride_details = {
                "request_id": ride.request_id,
                "pickup_location": ride.pickup_location,
                "dropoff_location": ride.dropoff_location,
                "status": ride.status.value if hasattr(ride.status, 'value') else str(ride.status),
                "requested_at": ride.requested_at.isoformat() if ride.requested_at else None,
                "estimated_price": ride.estimated_price,
                "distance_km": float(ride.distance_km) if ride.distance_km else None,
                "client_name": user.full_name if user else None,
                "client_phone": user.phone if user else None,
            }
            
            # Find assignment and driver
            assignment = db.query(RideAssignment).filter(
                RideAssignment.request_id == r.ride_id,
                RideAssignment.status == AssignmentStatus.ACCEPTED
            ).first()
            if assignment:
                taxi = db.query(Taxi).filter(Taxi.taxi_id == assignment.taxi_id).first()
                if taxi:
                    d_user = db.query(User).filter(User.user_id == taxi.driver_id).first()
                    driver = db.query(Driver).filter(Driver.driver_id == taxi.driver_id).first()
                    if d_user and driver:
                        driver_info = {
                            "driver_id": driver.driver_id,
                            "name": d_user.full_name,
                            "phone": d_user.phone,
                            "email": d_user.email,
                            "average_rating": driver.average_rating,
                            "license_number": driver.license_number,
                            "plate_number": taxi.plate_number,
                            "vehicle_model": taxi.vehicle_model,
                        }
                
        res.append({
            "report_id": r.report_id,
            "ride_id": r.ride_id,
            "report_type": r.report_type,
            "severity_level": r.severity_level,
            "description": r.description,
            "status": r.status.lower() if r.status else "open",
            "reporter_name": reporter_name,
            "created_at": r.created_at.isoformat() if r.created_at else datetime.utcnow().isoformat(),
            "resolution_note": r.resolution_note,
            "driver": driver_info,
            "ride": ride_details,
        })
    return res

@router.put("/reports/{report_id}/status")
def update_report_status(report_id: int, payload: ReportStatusUpdate, db: Session = Depends(get_db)):
    report = db.query(IncidentReport).filter(IncidentReport.report_id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    report.status = payload.status.upper()
    report.resolution_note = payload.resolution_note
    db.commit()
    return {"message": "Report status updated"}

@router.put("/drivers/{driver_id}/rating")
def update_driver_rating(driver_id: int, payload: RatingUpdatePayload, db: Session = Depends(get_db)):
    driver = db.query(Driver).filter(Driver.driver_id == driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")
    driver.average_rating = payload.average_rating
    db.commit()
    return {"message": "Driver rating updated successfully"}

import asyncio
from fastapi import WebSocket, WebSocketDisconnect
from app.database.connection import SessionLocal

@router.websocket("/locations/ws")
async def websocket_admin_locations(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            db = SessionLocal()
            try:
                drivers = db.query(Driver).filter(Driver.is_active == True).all()
                for driver in drivers:
                    status = "offline"
                    if driver.is_available:
                        status = "available"
                        active_assignment = db.query(RideAssignment).join(Taxi).filter(
                            Taxi.driver_id == driver.driver_id,
                            RideAssignment.status == AssignmentStatus.ACCEPTED
                        ).first()
                        if active_assignment:
                            ride = db.query(RideRequest).filter(RideRequest.request_id == active_assignment.request_id).first()
                            if ride and ride.status in [RideStatusEnum.ACCEPTED, RideStatusEnum.IN_PROGRESS]:
                                status = "occupied"
                                
                    lat = float(driver.current_lat) if driver.current_lat is not None else None
                    lng = float(driver.current_lng) if driver.current_lng is not None else None
                    
                    data = {
                        "driver_id": driver.driver_id,
                        "driver_name": driver.full_name,
                        "driver_phone": driver.phone,
                        "status": status,
                        "speed": 0,
                        "latitude": lat,
                        "longitude": lng,
                        "heading": 0
                    }
                    
                    await websocket.send_json(data)
            finally:
                db.close()
            await asyncio.sleep(3)
    except WebSocketDisconnect:
        pass
