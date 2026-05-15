from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from app.database.connection import get_db
from app.controllers.driver_controller import DriverController

router = APIRouter(tags=["driver"])

@router.get("/profile/{user_id}")
async def get_driver_profile(user_id: int, db: Session = Depends(get_db)):
    return DriverController.get_profile(db, user_id)

@router.put("/profile/{user_id}")
async def update_profile(user_id: int, data: dict, db: Session = Depends(get_db)):
    return DriverController.update_profile(db, user_id, data)

@router.get("/rides/available")
async def get_available_rides(driver_id: Optional[int] = Query(None), db: Session = Depends(get_db)):
    return DriverController.get_available_rides(db, driver_id=driver_id)

@router.post("/rides/{request_id}/accept")
async def accept_ride(request_id: int, driver_id: Optional[int] = Query(None), db: Session = Depends(get_db)):
    return DriverController.accept_ride(db, request_id, driver_id)

@router.get("/rides/accepted/{user_id}")
async def get_accepted_rides(user_id: int, db: Session = Depends(get_db)):
    return DriverController.get_accepted_rides(db, user_id)

@router.get("/rides/active/{user_id}")
async def get_active_ride(user_id: int, db: Session = Depends(get_db)):
    return DriverController.get_active_ride(db, user_id)

@router.get("/rides/history/{user_id}")
async def get_driver_history(user_id: int, db: Session = Depends(get_db)):
    return DriverController.get_driver_history(db, user_id)

@router.put("/rides/{request_id}/status")
async def update_ride_status(request_id: int, payload: dict, db: Session = Depends(get_db)):
    return DriverController.update_ride_status(db, request_id, payload.get("action"))

@router.get("/taxi/{user_id}")
async def get_taxi_info(user_id: int, db: Session = Depends(get_db)):
    return DriverController.get_taxi_info(db, user_id)

@router.put("/status/{user_id}")
async def update_driver_status(user_id: int, payload: dict, db: Session = Depends(get_db)):
    return DriverController.update_driver_status(db, user_id, payload.get("is_online", True))

@router.put("/location/{user_id}")
async def update_driver_location(user_id: int, payload: dict, db: Session = Depends(get_db)):
    return DriverController.update_driver_location(db, user_id, payload.get("lat"), payload.get("lng"))
