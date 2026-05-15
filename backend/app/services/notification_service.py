import os
import firebase_admin
from firebase_admin import credentials, messaging

# Initialize Firebase Admin SDK
def init_firebase():
    if not firebase_admin._apps:
        # On utilise un nom de fichier générique pour plus de sécurité (ignoré par git)
        cred_path = os.path.join(os.path.dirname(__file__), "..", "firebase-adminsdk.json")
        
        if not os.path.exists(cred_path):
            print(f"ATTENTION: Le fichier de credentials Firebase est manquant à l'emplacement: {cred_path}")
            print("Les notifications push ne fonctionneront pas tant que ce fichier n'est pas ajouté.")
            return

        try:
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            print("Firebase Admin initialisé avec succès.")
        except Exception as e:
            print(f"Erreur lors de l'initialisation de Firebase Admin : {e}")

init_firebase()

def send_push_notification(fcm_token: str, title: str, body: str, data: dict = None):
    """
    Envoie une notification push via FCM.
    """
    if not fcm_token:
        return False

    # S'assurer que Firebase est initialisé
    if not firebase_admin._apps:
        init_firebase()
    
    if not firebase_admin._apps:
        print("Erreur : Impossible d'envoyer la notification car Firebase n'est pas initialisé (fichier manquant ?).")
        return False

    try:
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data=data if data else {},
            token=fcm_token,
        )
        response = messaging.send(message)
        print(f"Notification envoyée avec succès : {response}")
        return True
    except Exception as e:
        print(f"Erreur lors de l'envoi de la notification : {e}")
        return False
