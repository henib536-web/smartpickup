from datetime import datetime
import math
from fastapi import HTTPException
from sqlalchemy import String
from sqlalchemy.orm import Session
from app.models.ride_request import RideRequest
from app.models.ride_assignment import RideAssignment
from app.models.driver import Driver
from app.models.taxi import Taxi
from app.models.ride_log import RideLog
from app.models.base_enums import RideStatusEnum, AssignmentStatus, UserRoleEnum
from app.models.passenger import Passenger
from app.models.notification import NotificationModel
from app.services.notification_service import send_push_notification
from app.models.user import User
from app.models.recurring_schedule import RecurringSchedule
from datetime import datetime, timedelta, time

class DriverController:
    @staticmethod
    def get_profile(db: Session, user_id: int):
        driver = db.query(Driver).filter(Driver.driver_id == user_id).first()
        if not driver:
            raise HTTPException(status_code=404, detail="Driver not found")
        
        # Also fetch total trips
        taxi = db.query(Taxi).filter(Taxi.driver_id == user_id).first()
        total_trips = 0
        if taxi:
            from app.models.ride_assignment import RideAssignment
            from app.models.base_enums import AssignmentStatus
            total_trips = db.query(RideAssignment).filter(
                RideAssignment.taxi_id == taxi.taxi_id,
                RideAssignment.status == AssignmentStatus.ACCEPTED
            ).count()

        return {
            "user_id": driver.driver_id,
            "full_name": driver.full_name,
            "email": driver.email,
            "phone": driver.phone,
            "license_number": driver.license_number,
            "average_rating": driver.average_rating,
            "is_active": driver.is_active,
            "is_available": driver.is_available,
            "image_url": driver.image_url,
            "total_trips": total_trips,
        }

    @staticmethod
    def update_profile(db: Session, user_id: int, data: dict):
        driver = db.query(Driver).filter(Driver.driver_id == user_id).first()
        if not driver:
            raise HTTPException(status_code=404, detail="Driver not found")
        
        if "full_name" in data: driver.full_name = data["full_name"]
        if "email" in data: driver.email = data["email"]
        if "phone" in data: driver.phone = data["phone"]
        if "license_number" in data: driver.license_number = data["license_number"]
        
        db.commit()
        db.refresh(driver)
        return driver

    @staticmethod
    def update_driver_location(db: Session, user_id: int, lat: float, lng: float):
        driver = db.query(Driver).filter(Driver.driver_id == user_id).first()
        if driver:
            driver.current_lat = lat
            driver.current_lng = lng
            driver.last_location_update = datetime.utcnow()
            db.commit()
        return {"status": "success"}

    @staticmethod
    def _calculate_distance(lat1, lon1, lat2, lon2):
        if None in [lat1, lon1, lat2, lon2]: return 999999
        R = 6371 # Earth radius in km
        dlat = math.radians(lat2 - lat1)
        dlon = math.radians(lon2 - lon1)
        a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
        return R * c

    @staticmethod
    def auto_offline_stale_drivers(db: Session):
        from datetime import datetime, timedelta
        timeout_threshold = datetime.utcnow() - timedelta(minutes=5)
        from sqlalchemy import or_
        stale_drivers = db.query(Driver).filter(
            Driver.is_available == True,
            or_(
                Driver.last_location_update == None,
                Driver.last_location_update < timeout_threshold
            )
        ).all()
        for d in stale_drivers:
            d.is_available = False
        if stale_drivers:
            db.commit()

    @staticmethod
    def _get_top_10_closest_drivers(db: Session, lat: float, lng: float):
        DriverController.auto_offline_stale_drivers(db)
        drivers = db.query(Driver).filter(
            Driver.is_available == True,
            Driver.current_lat != None,
            Driver.current_lng != None
        ).all()
        
        # Sort by distance and filter by 20km
        drivers_with_dist = []
        for d in drivers:
            dist = DriverController._calculate_distance(lat, lng, d.current_lat, d.current_lng)
            if dist <= 20: # Only within 20km (Strict limit)
                drivers_with_dist.append((d, dist))
        
        drivers_with_dist.sort(key=lambda x: x[1])
        return [d[0] for d in drivers_with_dist[:10]]

    @staticmethod
    def get_available_rides(db: Session, driver_id: int = None):
        # 1. GENERATE RIDE REQUESTS FROM RECURRING SCHEDULES (30 min window)
        now = datetime.now() # Use local server time or handle UTC properly
        today_enum = now.strftime('%A').upper() # "MONDAY", etc.
        
        # Search for active schedules for today
        active_schedules = db.query(RecurringSchedule).filter(
            RecurringSchedule.is_active == True,
            RecurringSchedule.day_of_week == today_enum,
            RecurringSchedule.start_date <= now.date(),
            RecurringSchedule.end_date >= now.date()
        ).all()

        for schedule in active_schedules:
            # Check if pickup_time is within 30 minutes
            sched_time = schedule.pickup_time
            # Convert schedule time to today's datetime
            sched_datetime = datetime.combine(now.date(), sched_time)
            
            # If (sched_datetime - 30min) <= now < sched_datetime
            if (sched_datetime - timedelta(minutes=30)) <= now <= sched_datetime:
                # Check if we already created a request for this schedule today
                existing = db.query(RideRequest).filter(
                    RideRequest.schedule_id == schedule.schedule_id,
                    RideRequest.scheduled_for >= datetime.combine(now.date(), time(0,0)),
                    RideRequest.scheduled_for <= datetime.combine(now.date(), time(23,59))
                ).first()
                
                if not existing:
                    # Link to a passenger (lookup or create for this client)
                    passenger = db.query(Passenger).filter(Passenger.full_name == (db.query(User).filter(User.user_id == schedule.client_id).first().full_name if db.query(User).filter(User.user_id == schedule.client_id).first() else "Client")).first()
                    if not passenger:
                        passenger = Passenger(full_name="Client", type="Standard")
                        db.add(passenger)
                        db.flush()

                    # Create the RideRequest automatically
                    new_ride = RideRequest(
                        client_id=schedule.client_id,
                        passenger_id=passenger.passenger_id,
                        zone_id=schedule.zone_id,
                        schedule_id=schedule.schedule_id,
                        pickup_location=schedule.pickup_location,
                        dropoff_location=schedule.dropoff_location,
                        pickup_lat=schedule.pickup_lat if hasattr(schedule, 'pickup_lat') and schedule.pickup_lat else 36.8,
                        pickup_lng=schedule.pickup_lng if hasattr(schedule, 'pickup_lng') and schedule.pickup_lng else 10.1,
                        dropoff_lat=schedule.dropoff_lat if hasattr(schedule, 'dropoff_lat') and schedule.dropoff_lat else 36.8,
                        dropoff_lng=schedule.dropoff_lng if hasattr(schedule, 'dropoff_lng') and schedule.dropoff_lng else 10.1,
                        scheduled_for=sched_datetime,
                        status=RideStatusEnum.PENDING,
                        requested_at=now,
                        # Copier le prix estimé et le prix prioritaire depuis le planning récurrent
                        estimated_price=schedule.estimated_price,
                        priority_price=float(schedule.priority_price) if schedule.priority_price is not None else 2.0,
                    )
                    db.add(new_ride)
                    db.commit()
                    db.refresh(new_ride)

                    # Trigger Notification for the top 10 closest drivers
                    try:
                        top_drivers = DriverController._get_top_10_closest_drivers(db, float(new_ride.pickup_lat), float(new_ride.pickup_lng))
                        for driver in top_drivers:
                            # Get user object for FCM token
                            user = db.query(User).filter(User.user_id == driver.driver_id).first()
                            if user and user.fcm_token:
                                send_push_notification(
                                    user.fcm_token, 
                                    "🆕 Course proche disponible !", 
                                    f"De {new_ride.pickup_location} (30 min avant départ)",
                                    {"type": "new_ride_available", "request_id": str(new_ride.request_id)}
                                )
                    except Exception as e:
                        print(f"Error sending recurring notification: {e}")

        # 2. FETCH ALL PENDING RIDES
        results = db.query(RideRequest, Passenger).outerjoin(
            Passenger, RideRequest.passenger_id == Passenger.passenger_id
        ).filter(RideRequest.status == RideStatusEnum.PENDING).all()
        
        rides = []
        current_driver = None
        if driver_id:
            current_driver = db.query(Driver).filter(Driver.driver_id == driver_id).first()
            if not current_driver:
                print(f"[WARNING] driver_id={driver_id} not found in Driver table!")
            elif current_driver.current_lat is None or current_driver.current_lng is None:
                print(f"[WARNING] driver_id={driver_id} has no location in DB (current_lat/lng is NULL). Will show all rides.")
            else:
                if not current_driver.is_available:
                    print(f"[WARNING] driver_id={driver_id} is marked as NOT available (is_available=False). Will be excluded from top10.")
                print(f"[DEBUG] Driver {driver_id} position: lat={current_driver.current_lat}, lng={current_driver.current_lng}, is_available={current_driver.is_available}")

        now = datetime.now()

        for ride, passenger in results:
            # Check if ride is expired
            is_expired = False
            if ride.scheduled_for:
                # Expire scheduled rides 15 minutes after their scheduled time
                if (now - ride.scheduled_for).total_seconds() > 900:
                    is_expired = True
            else:
                if ride.requested_at:
                    # Expire ASAP rides after 15 minutes (900 seconds)
                    if (now - ride.requested_at).total_seconds() > 900: 
                        is_expired = True
            
            if is_expired:
                continue

            # Check if this driver is among top 10 for this ride
            is_visible = True
            if current_driver and ride.pickup_lat and ride.pickup_lng:
                # If the driver has no location, show all rides (no filtering possible)
                if current_driver.current_lat is None or current_driver.current_lng is None:
                    is_visible = True
                else:
                    # Always calculate the real distance for debug purposes
                    real_dist = round(DriverController._calculate_distance(
                        float(current_driver.current_lat), float(current_driver.current_lng),
                        float(ride.pickup_lat), float(ride.pickup_lng)
                    ), 2)
                    top_10 = DriverController._get_top_10_closest_drivers(
                        db, float(ride.pickup_lat), float(ride.pickup_lng)
                    )
                    is_visible = any(d.driver_id == driver_id for d in top_10)
                    if not is_visible:
                        print(f"[DEBUG] Ride {ride.request_id} hidden from driver {driver_id} | distance={real_dist} km | is_available={current_driver.is_available}")
                    else:
                        print(f"[DEBUG] Ride {ride.request_id} visible to driver {driver_id} | distance={real_dist} km")

            if not is_visible:
                continue

            # Calculate real distance for this driver if available
            distance_km = 5.4  # default mock
            if current_driver and current_driver.current_lat and current_driver.current_lng and ride.pickup_lat and ride.pickup_lng:
                distance_km = round(DriverController._calculate_distance(
                    float(current_driver.current_lat), float(current_driver.current_lng),
                    float(ride.pickup_lat), float(ride.pickup_lng)
                ), 1)

            rides.append({
                "request_id": ride.request_id,
                "passenger_name": passenger.full_name if passenger else "Client",
                "passenger_type": passenger.type if passenger else "Standard",
                "pickup_location": ride.pickup_location,
                "dropoff_location": ride.dropoff_location,
                "pickup_lat": float(ride.pickup_lat) if ride.pickup_lat is not None else None,
                "pickup_lng": float(ride.pickup_lng) if ride.pickup_lng is not None else None,
                "dropoff_lat": float(ride.dropoff_lat) if ride.dropoff_lat is not None else None,
                "dropoff_lng": float(ride.dropoff_lng) if ride.dropoff_lng is not None else None,
                "scheduled_for": ride.scheduled_for,
                "requested_at": (ride.requested_at.isoformat() + "Z") if ride.requested_at else None,
                "distance_km": distance_km,
                "time_mins": 12,
                "priority_price": float(ride.priority_price) if ride.priority_price is not None else 2.0,
                "estimated_price": ride.estimated_price,
                "base_price": 3500,
            })
        
        # 3. SORT BY PRIORITY PRICE (Highest first)
        rides.sort(key=lambda x: x['priority_price'], reverse=True)
        
        return rides

    @staticmethod
    def accept_ride(db: Session, request_id: int, driver_id: int = None):
        ride = db.query(RideRequest).filter(RideRequest.request_id == request_id).first()
        if not ride:
            raise HTTPException(status_code=404, detail="Ride request not found")
        
        if ride.status != RideStatusEnum.PENDING:
            raise HTTPException(status_code=400, detail="Ride is no longer available")
        
        # Chercher le taxi du chauffeur spécifique
        taxi = None
        if driver_id:
            taxi = db.query(Taxi).filter(Taxi.driver_id == driver_id).first()
        
        # Fallback si aucun driver_id ou si le taxi n'existe pas encore (pour le dev)
        if not taxi:
            if driver_id:
                # Créer un taxi pour ce chauffeur spécifique
                taxi = Taxi(
                    driver_id=driver_id, 
                    plate_number=f"TUN-{driver_id}00", 
                    vehicle_model="Volkswagen Golf", 
                    availability=True
                )
                db.add(taxi)
                try:
                    db.flush()
                except Exception as e:
                    db.rollback()
                    raise HTTPException(status_code=400, detail="Ce compte n'est pas un chauffeur valide (manquant dans la table drivers).")
            else:
                # Ancienne logique fallback (premier taxi trouvé)
                taxi = db.query(Taxi).first()
                if not taxi:
                    taxi = Taxi(driver_id=2, plate_number="MOCK-001", vehicle_model="Mercedes Classe E", availability=True)
                    db.add(taxi)
                    db.flush()

        ride.status = RideStatusEnum.ACCEPTED
        assignment = RideAssignment(
            request_id=request_id, 
            taxi_id=taxi.taxi_id, 
            status=AssignmentStatus.ACCEPTED, 
            responded_at=datetime.utcnow()
        )
        db.add(assignment)

        # Mettre à jour le log de la course
        new_log = RideLog(ride_id=request_id, amount_suggested=15.0, is_payment_confirmed=False)
        db.add(new_log)

        # Notifications
        DriverController._notify_ride_acceptance(db, ride, taxi)

        db.commit()
        return {"status": "success", "message": "Ride accepted", "driver_id": taxi.driver_id}

    @staticmethod
    def _notify_ride_acceptance(db, ride, taxi):
        client_title = "✅ Course Acceptée"
        client_body = f"Un chauffeur a accepté votre course de {ride.pickup_location}. Il arrive bientôt !"
        db.add(NotificationModel(user_id=ride.client_id, title=client_title, message=client_body, type="ride_accepted", is_read=False, created_at=datetime.utcnow()))
        
        client_user = db.query(User).filter(User.user_id == ride.client_id).first()
        if client_user and client_user.fcm_token:
            send_push_notification(client_user.fcm_token, client_title, client_body, {"type": "ride_accepted", "request_id": str(ride.request_id)})

        driver_title = "🚕 Course Confirmée"
        driver_body = f"Vous avez accepté la course de {ride.pickup_location}. En route !"
        db.add(NotificationModel(user_id=taxi.driver_id, title=driver_title, message=driver_body, type="ride_accepted_driver", is_read=False, created_at=datetime.utcnow()))
        
        driver_user = db.query(User).filter(User.user_id == taxi.driver_id).first()
        if driver_user and driver_user.fcm_token:
            send_push_notification(driver_user.fcm_token, driver_title, driver_body, {"type": "ride_accepted_driver", "request_id": str(ride.request_id)})

    @staticmethod
    def get_accepted_rides(db: Session, user_id: int):
        taxi = db.query(Taxi).filter(Taxi.driver_id == user_id).first()
        if not taxi: return []
        
        assignments = db.query(RideAssignment).filter(
            RideAssignment.taxi_id == taxi.taxi_id, 
            RideAssignment.status == AssignmentStatus.ACCEPTED
        ).all()
        
        request_ids = [a.request_id for a in assignments]
        rides = db.query(RideRequest, Passenger).join(
            Passenger, RideRequest.passenger_id == Passenger.passenger_id
        ).filter(
            RideRequest.request_id.in_(request_ids),
            RideRequest.status == RideStatusEnum.ACCEPTED
        ).order_by(RideRequest.scheduled_for.asc()).all()
        
        now = datetime.now()
        
        result = []
        for ride, passenger in rides:
            is_today_and_active = False
            
            if ride.scheduled_for:
                if ride.scheduled_for.date() == now.date() and ride.scheduled_for >= now:
                    is_today_and_active = True
            else:
                if ride.requested_at and ride.requested_at.date() == now.date():
                    is_today_and_active = True
                    
            if not is_today_and_active:
                continue

            result.append({
                "request_id": ride.request_id,
                "passenger_name": passenger.full_name,
                "passenger_type": passenger.type,
                "pickup_location": ride.pickup_location,
                "dropoff_location": ride.dropoff_location,
                "scheduled_for": ride.scheduled_for.isoformat() if ride.scheduled_for else None,
                "pickup_lat": float(ride.pickup_lat) if ride.pickup_lat is not None else None,
                "pickup_lng": float(ride.pickup_lng) if ride.pickup_lng is not None else None,
                "dropoff_lat": float(ride.dropoff_lat) if ride.dropoff_lat is not None else None,
                "dropoff_lng": float(ride.dropoff_lng) if ride.dropoff_lng is not None else None,
                "distance_km": 5.4, # Mock
                "time_mins": 12, # Mock
                "estimated_price": ride.estimated_price,
                "base_price": 3500,
            })
        return result

    @staticmethod
    def get_active_ride(db: Session, user_id: int):
        taxi = db.query(Taxi).filter(Taxi.driver_id == user_id).first()
        if not taxi: return None
        
        # Get all accepted assignments
        assignments = db.query(RideAssignment).filter(
            RideAssignment.taxi_id == taxi.taxi_id, 
            RideAssignment.status == AssignmentStatus.ACCEPTED
        ).all()
        if not assignments: return None
        
        request_ids = [a.request_id for a in assignments]
        
        # Find the one with the closest scheduled_for time (nulls last or treated as "now")
        # We want the one where scheduled_for is earliest (if it's in the past or now)
        # or the absolute soonest.
        # Filter out stale rides: ignore ACCEPTED rides that were scheduled more than 24h ago
        # but keep IN_PROGRESS rides regardless of when they started.
        now = datetime.utcnow()
        recent_window = now - timedelta(hours=2)
        
        from app.models.base_enums import RideStatusEnum

        ride = db.query(RideRequest).filter(
            RideRequest.request_id.in_(request_ids),
            RideRequest.status.cast(String).in_(["ACCEPTED", "IN_PROGRESS"])
        ).filter(
            (RideRequest.status.cast(String) == "IN_PROGRESS") | 
            ((RideRequest.scheduled_for != None) & (RideRequest.scheduled_for >= recent_window)) |
            (RideRequest.scheduled_for == None)
        ).order_by(
            RideRequest.status.cast(String).desc(),
            RideRequest.request_id.desc()
        ).first()
        
        if not ride: return None
        
        # Fetch passenger name
        passenger = db.query(Passenger).filter(Passenger.passenger_id == ride.passenger_id).first() if ride.passenger_id else None
        client_user = db.query(User).filter(User.user_id == ride.client_id).first()
        
        passenger_name = "Passenger"
        if passenger:
            passenger_name = passenger.full_name
        elif client_user:
            passenger_name = client_user.full_name

        return {
            "request_id": ride.request_id,
            "client_id": ride.client_id,
            "passenger": passenger_name,
            "passenger_phone": client_user.phone if client_user else (passenger.phone if passenger and hasattr(passenger, 'phone') else None),
            "pickup_location": ride.pickup_location,
            "dropoff_location": ride.dropoff_location,
            "pickup": ride.pickup_location,
            "dropoff": ride.dropoff_location,
            "pickup_lat": float(ride.pickup_lat) if ride.pickup_lat is not None else None,
            "pickup_lng": float(ride.pickup_lng) if ride.pickup_lng is not None else None,
            "dropoff_lat": float(ride.dropoff_lat) if ride.dropoff_lat is not None else None,
            "dropoff_lng": float(ride.dropoff_lng) if ride.dropoff_lng is not None else None,
            "status": ride.status.value if hasattr(ride.status, "value") else str(ride.status),
            "ride_started": ride.status == RideStatusEnum.IN_PROGRESS or ride.status == "IN_PROGRESS",
            "scheduled_for": ride.scheduled_for.isoformat() if ride.scheduled_for else None,
        }

    @staticmethod
    def get_driver_history(db: Session, user_id: int):
        taxi = db.query(Taxi).filter(Taxi.driver_id == user_id).first()
        if not taxi: return []
        assignments = db.query(RideAssignment).filter(RideAssignment.taxi_id == taxi.taxi_id, RideAssignment.status == AssignmentStatus.ACCEPTED).all()
        request_ids = [a.request_id for a in assignments]
        
        now = datetime.now()
        
        rides_query = db.query(RideRequest, Passenger).outerjoin(
            Passenger, RideRequest.passenger_id == Passenger.passenger_id
        ).filter(
            RideRequest.request_id.in_(request_ids),
            RideRequest.status.cast(String).in_(["COMPLETED", "ACCEPTED"])
        ).order_by(RideRequest.scheduled_for.desc()).all()
        
        result = []
        for ride, passenger in rides_query:
            status_str = str(ride.status)
            is_passed = False
            
            if status_str == "ACCEPTED":
                if ride.scheduled_for and ride.scheduled_for < now:
                    is_passed = True
                elif ride.scheduled_for is None and ride.requested_at and ride.requested_at.date() < now.date():
                    is_passed = True
                    
                if not is_passed:
                    continue # Skip accepted rides that are not passed yet
            
            # Format date
            date_str = ride.scheduled_for.strftime("%Y-%m-%d %H:%M") if ride.scheduled_for else (ride.requested_at.strftime("%Y-%m-%d %H:%M") if ride.requested_at else "N/A")
            
            result.append({
                "id": ride.request_id,
                "date": date_str,
                "pickup": ride.pickup_location,
                "dropoff": ride.dropoff_location,
                "duration": "12 mins", # mock
                "rating": 5.0, # mock
                "status": "completed" if status_str == "COMPLETED" else "passed",
                "passenger": passenger.full_name if passenger else "Unknown"
            })
            
        return result

    @staticmethod
    def update_ride_status(db: Session, request_id: int, action: str):
        ride = db.query(RideRequest).filter(RideRequest.request_id == request_id).first()
        if not ride:
            raise HTTPException(status_code=404, detail="Ride request not found")
        
        if str(ride.status) == "CANCELLED":
            raise HTTPException(status_code=400, detail="Cannot update status: Ride is already cancelled")

        title, message = "", ""
        if action == "start":
            ride.status = "IN_PROGRESS"
            title, message = "🚗 Course Démarrée", "Votre trajet a commencé. Bon voyage !"
            log = db.query(RideLog).filter(RideLog.ride_id == request_id).first()
            if log: log.start_time = datetime.utcnow()
                
        elif action == "complete":
            ride.status = "COMPLETED"
            title, message = "🏁 Course Terminée", "Vous êtes arrivé à destination. Merci d'avoir voyagé avec nous !"
            log = db.query(RideLog).filter(RideLog.ride_id == request_id).first()
            if log:
                log.end_time = datetime.utcnow()
                log.is_payment_confirmed = True
        
        if title:
            db.add(NotificationModel(user_id=ride.client_id, title=title, message=message, type=f"ride_{action}", is_read=False, created_at=datetime.utcnow()))
            client_user = db.query(User).filter(User.user_id == ride.client_id).first()
            if client_user and client_user.fcm_token:
                send_push_notification(client_user.fcm_token, title, message, {"type": f"ride_{action}", "request_id": str(request_id)})
        
        db.commit()
        return {"status": "success", "message": f"Ride status updated to {ride.status}"}

    @staticmethod
    def get_driver_stats(db: Session, user_id: int):
        from sqlalchemy import func
        driver = db.query(Driver).filter(Driver.driver_id == user_id).first()
        if not driver:
            raise HTTPException(status_code=404, detail="Driver not found")

        taxi = db.query(Taxi).filter(Taxi.driver_id == user_id).first()
        if not taxi:
            return {
                "completed_rides": 0,
                "total_rides": 0,
                "average_rating": float(driver.average_rating) if driver.average_rating else 0.0,
                "acceptance_rate": 0.0,
                "today_rides": 0,
            }

        # All assignments for this taxi
        assignments = db.query(RideAssignment).filter(
            RideAssignment.taxi_id == taxi.taxi_id
        ).all()
        request_ids = [a.request_id for a in assignments]

        total_rides = len(request_ids)
        completed_rides = 0
        today_rides = 0
        if request_ids:
            completed_rides = db.query(func.count(RideRequest.request_id)).filter(
                RideRequest.request_id.in_(request_ids),
                RideRequest.status.cast(String) == "COMPLETED"
            ).scalar() or 0

            today_start = datetime.combine(datetime.now().date(), time(0, 0))
            today_rides = db.query(func.count(RideRequest.request_id)).filter(
                RideRequest.request_id.in_(request_ids),
                RideRequest.status.cast(String).in_(["COMPLETED", "ACCEPTED", "IN_PROGRESS"]),
                RideRequest.requested_at >= today_start
            ).scalar() or 0

        acceptance_rate = round(completed_rides / max(total_rides, 1) * 100, 1)

        return {
            "completed_rides": completed_rides,
            "total_rides": total_rides,
            "average_rating": float(driver.average_rating) if driver.average_rating else 0.0,
            "acceptance_rate": acceptance_rate,
            "today_rides": today_rides,
        }

    @staticmethod
    def get_taxi_info(db: Session, user_id: int):
        taxi = db.query(Taxi).filter(Taxi.driver_id == user_id).first()
        if not taxi:
            raise HTTPException(status_code=404, detail="Taxi not found")
        return {"taxi_id": taxi.taxi_id, "plate_number": taxi.plate_number, "vehicle_model": taxi.vehicle_model}

    @staticmethod
    def update_driver_status(db: Session, user_id: int, is_online: bool):
        driver = db.query(Driver).filter(Driver.driver_id == user_id).first()
        if driver:
            driver.is_available = is_online
            if is_online:
                driver.last_location_update = datetime.utcnow()
            db.commit()
        return {"status": "success", "is_online": is_online}
