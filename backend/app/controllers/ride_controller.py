from datetime import datetime
from typing import List, Optional
from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.base_enums import CancelledBy, DayOfWeek, RideStatusEnum
from app.models.client import Client
from app.models.passenger import Passenger
from app.models.recurring_schedule import RecurringSchedule
from app.models.ride_request import RideRequest
from app.models.user import User
from app.models.zone import Zone
from app.models.ride_rating import RideRating
from app.models.incident_rapport import IncidentReport
from app.models.notification import NotificationModel
from app.services.notification_service import send_push_notification
from app.models.ride_assignment import RideAssignment
from app.models.taxi import Taxi
from app.models.ride_log import RideLog
from app.models.driver import Driver
from app.models.base_enums import UserRoleEnum, AssignmentStatus

DAY_MAP = {
    "monday": DayOfWeek.MONDAY,
    "tuesday": DayOfWeek.TUESDAY,
    "wednesday": DayOfWeek.WEDNESDAY,
    "thursday": DayOfWeek.THURSDAY,
    "friday": DayOfWeek.FRIDAY,
    "saturday": DayOfWeek.SATURDAY,
    "sunday": DayOfWeek.SUNDAY,
}

class RideController:
    @staticmethod
    def book_ride(db: Session, ride_in):
        try:
            # 1. GESTION DE LA ZONE (Get or Create)
            zone = db.query(Zone).filter(Zone.zone_name == ride_in.zone_name).first()
            if not zone:
                zone = Zone(zone_name=ride_in.zone_name, city="Sousse")
                db.add(zone)
                db.flush()

            # 2. GESTION DU PASSAGER (Get or Create)
            client = db.query(Client).filter(Client.client_id == ride_in.client_id).first()
            if not client:
                user = db.query(User).filter(User.user_id == ride_in.client_id).first()
                if not user:
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND,
                        detail="Connected user not found",
                    )
                db.execute(Client.__table__.insert().values(client_id=ride_in.client_id))
                db.flush()
                client = db.query(Client).filter(Client.client_id == ride_in.client_id).first()

            passenger = None
            if ride_in.passenger_id is not None:
                passenger = db.query(Passenger).filter(Passenger.passenger_id == ride_in.passenger_id).first()

            if passenger is None:
                passenger = db.query(Passenger).filter(Passenger.full_name == ride_in.passenger_name).first()

            if not passenger:
                passenger = Passenger(
                    full_name=ride_in.passenger_name,
                    type=ride_in.passenger_type,
                )
                db.add(passenger)
                db.flush()

            # 3. SI RÉCURRENTE, CRÉER UNIQUEMENT LE PLANNING
            if ride_in.scheduled_flag and ride_in.start_date and ride_in.end_date:
                if not ride_in.selected_days:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="selected_days is required for recurring schedule",
                    )

                for day_str in ride_in.selected_days:
                    normalized_day = DAY_MAP.get(day_str.strip().lower())
                    if normalized_day is None:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Invalid day value: {day_str}",
                        )

                    schedule = RecurringSchedule(
                        client_id=ride_in.client_id,
                        zone_id=zone.zone_id,
                        day_of_week=normalized_day,
                        start_date=ride_in.start_date.date(),
                        end_date=ride_in.end_date.date(),
                        pickup_time=ride_in.pickup_time.time(),
                        pickup_location=ride_in.pickup_location,
                        dropoff_location=ride_in.dropoff_location,
                        pickup_lat=ride_in.pickup_lat,
                        pickup_lng=ride_in.pickup_lng,
                        dropoff_lat=ride_in.dropoff_lat,
                        dropoff_lng=ride_in.dropoff_lng,
                    )
                    db.add(schedule)

                db.commit()
                return {
                    "status": "success",
                    "request_id": None,
                    "message": "Recurring schedule created successfully",
                }

            # 4. CRÉATION D'UNE DEMANDE DE COURSE SIMPLE
            new_ride = RideRequest(
                client_id=ride_in.client_id,
                passenger_id=passenger.passenger_id,
                zone_id=zone.zone_id,
                pickup_location=ride_in.pickup_location,
                dropoff_location=ride_in.dropoff_location,
                pickup_lat=ride_in.pickup_lat,
                pickup_lng=ride_in.pickup_lng,
                dropoff_lat=ride_in.dropoff_lat,
                dropoff_lng=ride_in.dropoff_lng,
                scheduled_for=ride_in.pickup_time,
                status=RideStatusEnum.PENDING,
                requested_at=datetime.utcnow(),
                priority_price=ride_in.priority_price or 2.0,
            )

            db.add(new_ride)
            db.flush()

            # 5. NOTIFICATIONS
            RideController._notify_ride_creation(db, new_ride, ride_in)

            db.commit()
            db.refresh(new_ride)

            return {
                "status": "success",
                "request_id": new_ride.request_id,
                "message": f"Ride created successfully in {zone.zone_name}",
            }

        except HTTPException:
            db.rollback()
            raise
        except Exception as e:
            db.rollback()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Database error: {str(e)}",
            )

    @staticmethod
    def _notify_ride_creation(db, new_ride, ride_in):
        client_title = "🚕 Demande Envoyée"
        client_body = f"Votre demande de course de {ride_in.pickup_location} vers {ride_in.dropoff_location} a été envoyée aux chauffeurs."
        
        user_notif = NotificationModel(
            user_id=ride_in.client_id,
            title=client_title,
            message=client_body,
            type="ride_requested",
            is_read=False,
            created_at=datetime.utcnow()
        )
        db.add(user_notif)

        user = db.query(User).filter(User.user_id == ride_in.client_id).first()
        if user and user.fcm_token:
            send_push_notification(user.fcm_token, client_title, client_body, {"type": "ride_requested", "request_id": str(new_ride.request_id)})

        from app.controllers.driver_controller import DriverController
        driver_title = "🆕 Nouvelle course disponible !"
        driver_body = f"De {ride_in.pickup_location} vers {ride_in.dropoff_location}"
        try:
            top_drivers = DriverController._get_top_10_closest_drivers(db, float(new_ride.pickup_lat), float(new_ride.pickup_lng))
            for driver in top_drivers:
                user = db.query(User).filter(User.user_id == driver.driver_id).first()
                if user:
                    driver_notif = NotificationModel(
                        user_id=user.user_id,
                        title=driver_title,
                        message=driver_body,
                        type="new_ride_available",
                        is_read=False,
                        created_at=datetime.utcnow()
                    )
                    db.add(driver_notif)
                    if user.fcm_token:
                        send_push_notification(user.fcm_token, driver_title, driver_body, {"type": "new_ride_available", "request_id": str(new_ride.request_id)})
        except Exception as e:
            print(f"Error notifying closest drivers: {e}")

    @staticmethod
    def list_user_rides(db: Session, client_id: int):
        rides = db.query(RideRequest).filter(RideRequest.client_id == client_id).order_by(RideRequest.scheduled_for.desc()).all()
        schedules = db.query(RecurringSchedule).filter(RecurringSchedule.client_id == client_id).order_by(RecurringSchedule.start_date.desc(), RecurringSchedule.pickup_time.desc()).all()

        from app.schemas.ride import RideListItem
        ride_items = [
            RideListItem(
                item_type="ride_request",
                request_id=r.request_id,
                client_id=r.client_id,
                passenger_id=r.passenger_id,
                pickup_location=r.pickup_location,
                dropoff_location=r.dropoff_location,
                pickup_lat=r.pickup_lat,
                pickup_lng=r.pickup_lng,
                dropoff_lat=r.dropoff_lat,
                dropoff_lng=r.dropoff_lng,
                scheduled_for=r.scheduled_for,
                status=r.status.value if r.status and hasattr(r.status, "value") else (str(r.status) if r.status else "UNKNOWN"),
                is_recurring=r.schedule_id is not None,
            )
            for r in rides
        ]
        schedule_items = [
            RideListItem(
                item_type="recurring_schedule",
                schedule_id=s.schedule_id,
                client_id=s.client_id,
                pickup_location=s.pickup_location,
                dropoff_location=s.dropoff_location,
                status="ACTIVE" if s.is_active else "CANCELLED",
                is_recurring=True,
                recurring_day=s.day_of_week.value if s.day_of_week and hasattr(s.day_of_week, "value") else (str(s.day_of_week) if s.day_of_week else "N/A"),
            )
            for s in schedules
        ]
        return ride_items + schedule_items

    @staticmethod
    def cancel_ride(db: Session, request_id: int):
        ride = db.query(RideRequest).filter(RideRequest.request_id == request_id).first()
        if not ride:
            raise HTTPException(status_code=404, detail="Ride not found")

        if ride.status in (RideStatusEnum.CANCELLED, RideStatusEnum.COMPLETED):
            raise HTTPException(status_code=400, detail="Ride cannot be cancelled")

        ride.status = RideStatusEnum.CANCELLED
        ride.cancelled_by = CancelledBy.USER
        
        cancel_title = "❌ Course Annulée"
        cancel_body = f"La course de {ride.pickup_location} a été annulée."

        # Notification Client
        notif = NotificationModel(user_id=ride.client_id, title=cancel_title, message=cancel_body, type="ride_cancelled", is_read=False, created_at=datetime.utcnow())
        db.add(notif)
        client_user = db.query(User).filter(User.user_id == ride.client_id).first()
        if client_user and client_user.fcm_token:
            send_push_notification(client_user.fcm_token, cancel_title, cancel_body, {"type": "ride_cancelled"})

        # Notification Driver
        assignment = db.query(RideAssignment).filter(RideAssignment.request_id == request_id, RideAssignment.status == "ACCEPTED").first()
        if assignment:
            taxi = db.query(Taxi).filter(Taxi.taxi_id == assignment.taxi_id).first()
            if taxi:
                driver_notif = NotificationModel(user_id=taxi.driver_id, title=cancel_title, message=f"L'utilisateur a annulé la course prévue à {ride.pickup_location}.", type="ride_cancelled_driver", is_read=False, created_at=datetime.utcnow())
                db.add(driver_notif)
                driver_user = db.query(User).filter(User.user_id == taxi.driver_id).first()
                if driver_user and driver_user.fcm_token:
                    send_push_notification(driver_user.fcm_token, cancel_title, driver_notif.message, {"type": "ride_cancelled_driver"})

        db.commit()
        return {"status": "success", "request_id": ride.request_id, "message": "Ride cancelled successfully"}

    @staticmethod
    def cancel_schedule(db: Session, schedule_id: int):
        schedule = db.query(RecurringSchedule).filter(RecurringSchedule.schedule_id == schedule_id).first()
        if not schedule:
            raise HTTPException(status_code=404, detail="Schedule not found")
        schedule.is_active = False
        db.commit()
        return {"status": "success", "schedule_id": schedule.schedule_id, "message": "Schedule cancelled successfully"}

    @staticmethod
    def rate_ride(db: Session, request_id: int, payload: dict):
        rating_val = payload.get("rating")
        if not rating_val:
            raise HTTPException(status_code=400, detail="Rating is required")
        new_rating = RideRating(ride_id=request_id, user_id=payload.get("user_id"), rating=rating_val, comment=payload.get("comment"), created_at=datetime.utcnow())
        db.add(new_rating)
        db.commit()
        return {"status": "success", "message": "Rating submitted"}

    @staticmethod
    def report_incident(db: Session, request_id: int, payload: dict):
        new_report = IncidentReport(ride_id=request_id, report_type=payload.get("report_type"), severity_level=payload.get("severity_level"), status="OPEN")
        db.add(new_report)
        db.commit()
        return {"status": "success", "message": "Incident reported"}

    @staticmethod
    def get_ride_details(db: Session, request_id: int):
        ride = db.query(RideRequest).filter(RideRequest.request_id == request_id).first()
        if not ride:
            raise HTTPException(status_code=404, detail="Ride not found")
        
        # Get assignment if exists
        assignment = db.query(RideAssignment).filter(
            RideAssignment.request_id == request_id, 
            RideAssignment.status == AssignmentStatus.ACCEPTED
        ).first()
        
        driver_info = None
        if assignment:
            taxi = db.query(Taxi).filter(Taxi.taxi_id == assignment.taxi_id).first()
            if taxi:
                # Essayer de récupérer depuis la table Driver
                driver = db.query(Driver).filter(Driver.driver_id == taxi.driver_id).first()
                # Si non trouvé dans Driver, chercher dans User (cas où le profil driver est incomplet)
                user = db.query(User).filter(User.user_id == taxi.driver_id).first()
                
                if user:
                    driver_info = {
                        "name": user.full_name,
                        "phone": user.phone,
                        "rating": getattr(driver, 'average_rating', 4.8) if driver else 4.8,
                        "vehicle_make": taxi.vehicle_model.split(' ')[0] if taxi.vehicle_model and ' ' in taxi.vehicle_model else (taxi.vehicle_model or "Toyota"),
                        "vehicle_model": ' '.join(taxi.vehicle_model.split(' ')[1:]) if taxi.vehicle_model and ' ' in taxi.vehicle_model else "Camry",
                        "vehicle_color": "Silver",
                        "vehicle_plate": taxi.plate_number or "TUN-123"
                    }

        return {
            "request_id": ride.request_id,
            "pickup_location": ride.pickup_location,
            "dropoff_location": ride.dropoff_location,
            "pickup_lat": ride.pickup_lat,
            "pickup_lng": ride.pickup_lng,
            "dropoff_lat": ride.dropoff_lat,
            "dropoff_lng": ride.dropoff_lng,
            "status": ride.status.value if hasattr(ride.status, "value") else str(ride.status),
            "scheduled_for": ride.scheduled_for.isoformat() if ride.scheduled_for else None,
            "driver": driver_info,
            "debug_assignment_found": assignment is not None,
            "debug_taxi_found": 'taxi' in locals() and taxi is not None
        }
