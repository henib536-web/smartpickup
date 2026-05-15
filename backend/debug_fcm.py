
import os
import sys

# Ajouter le dossier parent au path pour pouvoir importer 'app'
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session
from app.database.connection import SessionLocal
from app.models.user import User

def check_fcm_tokens():
    db: Session = SessionLocal()
    try:
        users = db.query(User).all()
        print("\n=== Liste des Utilisateurs et Tokens FCM ===\n")
        print(f"{'ID':<5} | {'Nom':<20} | {'Email':<30} | {'FCM Token Status'}")
        print("-" * 80)
        for user in users:
            status = "[OK]" if user.fcm_token else "[MISSING]"
            print(f"{user.user_id:<5} | {user.full_name:<20} | {user.email:<30} | {status}")
            if user.fcm_token:
                # On affiche juste le début du token pour des raisons de clarté
                print(f"      Token: {user.fcm_token[:50]}...")
        print("\n" + "=" * 45)
    except Exception as e:
        print(f"Erreur : {e}")
    finally:
        db.close()

if __name__ == "__main__":
    check_fcm_tokens()
