import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base,Session
from dotenv import load_dotenv

# Charge les variables d'environnement à partir du fichier .env si présent
load_dotenv()

# Connexion à PostgreSQL (utilise DATABASE_URL si présent, sinon fallback sur les identifiants locaux corrigés)
SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:user@127.0.0.1/smartpickup")

engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()
def get_db():
    db: Session = SessionLocal()
    try:
        yield db
    finally:
        db.close()