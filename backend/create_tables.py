from app.database.connection import Base, engine
from app.models import *

# Crée toutes les tables
Base.metadata.create_all(bind=engine)

print("Toutes les tables ont été créées !")