from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List


class RideCreateRequest(BaseModel):
    client_id: int
    passenger_id: Optional[int] = None
    passenger_name: str
    passenger_type: str
    zone_name: str  # Exemple: "Jemmel", "Msaken"
    pickup_location: str
    dropoff_location: str
    pickup_lat: float
    pickup_lng: float
    dropoff_lat: float
    dropoff_lng: float
    pickup_time: datetime
    scheduled_flag: bool
    # Champs utilisés uniquement si la course est récurrente
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    selected_days: Optional[List[str]] = None
    priority_price: Optional[float] = 2.0
    distance_km: Optional[float] = None
    estimated_price: Optional[int] = None  # Prix en millimes


class RideResponse(BaseModel):
    status: str
    request_id: Optional[int]
    message: str


class RideListItem(BaseModel):
    item_type: str
    request_id: Optional[int] = None
    schedule_id: Optional[int] = None
    client_id: Optional[int] = None
    passenger_id: Optional[int] = None
    passenger_name: Optional[str] = None
    pickup_location: str
    dropoff_location: str
    pickup_lat: Optional[float] = None
    pickup_lng: Optional[float] = None
    dropoff_lat: Optional[float] = None
    dropoff_lng: Optional[float] = None
    scheduled_for: Optional[datetime] = None
    status: str
    is_recurring: bool
    recurring_day: Optional[str] = None
    estimated_price: Optional[int] = None
    distance_km: Optional[float] = None
    rating: Optional[int] = None
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None