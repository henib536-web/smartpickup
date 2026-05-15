from fastapi import HTTPException, status, UploadFile
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from jose import jwt
from passlib.context import CryptContext
from typing import Optional
import os
import shutil
import uuid
from dotenv import load_dotenv

from app.models.email_verification import EmailVerificationCode
from app.services.email_service import verify_code_hash

load_dotenv()

SECRET_KEY = os.getenv("SECRET_KEY", "votre_cle_secrete_tres_longue_et_sure_123")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")
UPLOAD_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "uploads"))
os.makedirs(UPLOAD_DIR, exist_ok=True)

def _normalize_email(email: str) -> str:
    return email.lower().strip()

def _random_six_digit_code() -> str:
    import secrets
    return f"{secrets.randbelow(1000000):06d}"

def _verify_code_or_raise(db: Session, email: str, code: str, purpose: str) -> None:
    code = code.strip()
    if len(code) != 6 or not code.isdigit():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Le code doit contenir 6 chiffres.")
    
    email_n = _normalize_email(email)
    row = (
        db.query(EmailVerificationCode)
        .filter(
            EmailVerificationCode.email == email_n,
            EmailVerificationCode.purpose == purpose,
            EmailVerificationCode.used.is_(False),
            EmailVerificationCode.expires_at > datetime.utcnow(),
        )
        .order_by(EmailVerificationCode.id.desc())
        .first()
    )
    if not row or not verify_code_hash(email, code, row.code_hash):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Code invalide ou expiré.")
    row.used = True

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: timedelta = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def save_upload_file(upload_file: Optional[UploadFile]) -> Optional[str]:
    if upload_file is None or not upload_file.filename:
        return None

    extension = os.path.splitext(upload_file.filename)[1] or ".jpg"
    filename = f"{uuid.uuid4().hex}{extension}"
    destination = os.path.join(UPLOAD_DIR, filename)

    with open(destination, "wb") as buffer:
        shutil.copyfileobj(upload_file.file, buffer)

    return f"/uploads/{filename}"