from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base,Session

# Connexion à PostgreSQL
# user = postgres, password = root, db = smartpickup
SQLALCHEMY_DATABASE_URL = "postgresql://postgres:root@127.0.0.1/smartpickup"

engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()
def get_db():
    db: Session = SessionLocal()
    try:
        yield db
    finally:
        db.close()