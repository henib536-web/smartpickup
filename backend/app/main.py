from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.database.connection import engine, Base
from app.routes import user_routes, rides, notif_routes, driver_routes, admin_routes, auth_routes
import app.models
import os
# Create tables
try:
    Base.metadata.create_all(bind=engine)
except Exception as e:
    import sys
    print("\n" + "="*80)
    print("ERREUR DE CONNEXION A LA BASE DE DONNEES POSTGRESQL")
    print("="*80)
    print("Impossible de se connecter a la base de donnees PostgreSQL.")
    print("Veuillez verifier que :")
    print("1. Le service PostgreSQL (ex: postgresql-x64-18) est bien demarre.")
    print("2. Les identifiants dans 'app/database/connection.py' sont corrects.")
    print("3. La base de donnees 'smartpickup' existe.")
    
    if isinstance(e, UnicodeDecodeError):
        print("\nNote : Une erreur d'encodage (UnicodeDecodeError) a ete detectee.")
        print("Cela se produit sur Windows en francais lorsque PostgreSQL est arrete.")
        print("Le message d'erreur systeme contient des caracteres accentues que psycopg2 n'arrive pas a decoder.")
    else:
        print(f"\nDetails : {e}")
    print("="*80 + "\n")
    sys.exit(1)

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
