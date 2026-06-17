from typing import List, Dict
from fastapi import APIRouter, Depends, status, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from app.database.connection import get_db
from app.schemas.ride import RideCreateRequest, RideResponse, RideListItem
from app.controllers.ride_controller import RideController

router = APIRouter(prefix="/rides", tags=["rides"])


@router.post("/book", response_model=RideResponse, status_code=status.HTTP_201_CREATED)
async def book_ride(ride_in: RideCreateRequest, db: Session = Depends(get_db)):
    return RideController.book_ride(db, ride_in)


@router.get("/user/{client_id}", response_model=List[RideListItem])
async def list_user_rides(client_id: int, db: Session = Depends(get_db)) -> List[RideListItem]:
    return RideController.list_user_rides(db, client_id)


@router.get("/{request_id}")
async def get_ride_details(request_id: int, db: Session = Depends(get_db)):
    return RideController.get_ride_details(db, request_id)


@router.post("/{request_id}/cancel")
async def cancel_ride(request_id: int, db: Session = Depends(get_db)):
    return RideController.cancel_ride(db, request_id)


@router.post("/schedules/{schedule_id}/cancel")
async def cancel_schedule(schedule_id: int, db: Session = Depends(get_db)):
    return RideController.cancel_schedule(db, schedule_id)


@router.post("/{request_id}/rate")
async def rate_ride(request_id: int, payload: dict, db: Session = Depends(get_db)):
    return RideController.rate_ride(db, request_id, payload)


@router.post("/{request_id}/report")
async def report_incident(request_id: int, payload: dict, db: Session = Depends(get_db)):
    return RideController.report_incident(db, request_id, payload)


# --- WebSocket Manager for Real-time Tracking ---
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[int, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, ride_id: int):
        await websocket.accept()
        if ride_id not in self.active_connections:
            self.active_connections[ride_id] = []
        self.active_connections[ride_id].append(websocket)
        print(f"WS CONNECT: ride_id={ride_id}, total_connections={len(self.active_connections[ride_id])}")

    def disconnect(self, websocket: WebSocket, ride_id: int):
        if ride_id in self.active_connections and websocket in self.active_connections[ride_id]:
            self.active_connections[ride_id].remove(websocket)
            if len(self.active_connections[ride_id]) == 0:
                del self.active_connections[ride_id]
        print(f"WS DISCONNECT: ride_id={ride_id}")

    async def broadcast_to_ride(self, message: dict, ride_id: int, sender: WebSocket = None):
        """Broadcast a message to all clients on a ride, excluding the sender."""
        if ride_id not in self.active_connections:
            return
        dead = []
        for connection in self.active_connections[ride_id]:
            if connection is sender:
                continue  # Don't echo back to the driver who sent it
            try:
                await connection.send_json(message)
            except Exception:
                dead.append(connection)
        for d in dead:
            self.active_connections[ride_id].remove(d)

manager = ConnectionManager()

@router.websocket("/{request_id}/ws")
async def websocket_ride_endpoint(websocket: WebSocket, request_id: int):
    await manager.connect(websocket, request_id)
    try:
        while True:
            data = await websocket.receive_json()
            # If it's a ping from the client, ignore it
            if data.get("type") == "client_ping":
                await websocket.send_json({"type": "pong"})
                continue
            # The driver sends {"lat": 36.8, "lng": 10.1}
            # Add type so client can identify it as a location update
            data["type"] = "location_update"
            print(f"WS BROADCAST: ride_id={request_id}, lat={data.get('lat')}, lng={data.get('lng')}")
            # Broadcast to all OTHER connections on this ride (not back to driver)
            await manager.broadcast_to_ride(data, request_id, sender=websocket)
    except WebSocketDisconnect:
        manager.disconnect(websocket, request_id)