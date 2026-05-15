from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.database.connection import engine, Base
from app.routes import user_routes, rides, notif_routes, driver_routes, admin_routes, auth_routes
import app.models
import os
# Create tables
Base.metadata.create_all(bind=engine)

app = FastAPI(title="Smart Pickup API")

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    # Dev: Flutter Web uses random localhost ports,
    # so we allow all origins (no cookies).
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(auth_routes.router)
app.include_router(user_routes.router)
app.include_router(notif_routes.router)
app.include_router(rides.router)
app.include_router(driver_routes.router, prefix="/api/driver")
app.include_router(admin_routes.router)
uploads_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "uploads"))
os.makedirs(uploads_dir, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=uploads_dir), name="uploads")
@app.get("/")
def read_root():
    return {"message": "Smart Pickup API is running"}
