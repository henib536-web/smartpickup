import hashlib
import hmac
import os
import smtplib
from email.message import EmailMessage

from dotenv import load_dotenv

load_dotenv()

SECRET_KEY = os.getenv("SECRET_KEY", "votre_cle_secrete_tres_longue_et_sure_123")
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
SMTP_FROM = os.getenv("SMTP_FROM", SMTP_USER)


def hash_verification_code(email: str, code: str) -> str:
    return hmac.new(
        SECRET_KEY.encode(),
        f"{email.lower().strip()}:{code}".encode(),
        hashlib.sha256,
    ).hexdigest()


def verify_code_hash(email: str, code: str, stored_hash: str) -> bool:
    return hmac.compare_digest(hash_verification_code(email, code), stored_hash)


def send_email(to_address: str, subject: str, body: str) -> None:
    if not SMTP_USER or not SMTP_PASSWORD:
        print("\n" + "="*50)
        print("🚨 AVERTISSEMENT SMTP NON CONFIGURÉ 🚨")
        print(f"To: {to_address}")
        print(f"Subject: {subject}")
        print(f"Body: \n{body}")
        print("="*50 + "\n")
        return

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = SMTP_FROM or SMTP_USER
    msg["To"] = to_address
    msg.set_content(body)

    print(f"📧 Tentative d'envoi d'email à : {to_address}")

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
        server.starttls()
        server.login(SMTP_USER, SMTP_PASSWORD)
        server.send_message(msg)


def send_signup_code_email(to_address: str, code: str) -> None:
    subject = "Smart Pickup — Vérification de votre inscription"
    body = (
        f"Votre code de vérification est : {code}\n\n"
        "Ce code expire dans 15 minutes.\n"
        "Si vous n'avez pas demandé ce message, ignorez-le."
    )
    send_email(to_address, subject, body)


def send_password_reset_code_email(to_address: str, code: str) -> None:
    subject = "Smart Pickup — Réinitialisation du mot de passe"
    body = (
        f"Votre code de réinitialisation est : {code}\n\n"
        "Ce code expire dans 15 minutes.\n"
        "Si vous n'avez pas demandé cette réinitialisation, ignorez ce message."
    )
    send_email(to_address, subject, body)
