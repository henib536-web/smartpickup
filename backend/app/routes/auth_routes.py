from fastapi import APIRouter, HTTPException, Depends, status, Form, UploadFile, File
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from jose import JWTError, jwt

from app.database.connection import get_db
from app.controllers.auth_controller import AuthController
from app.services.auth_service import oauth2_scheme, SECRET_KEY, ALGORITHM

router = APIRouter(prefix="/auth", tags=["authentication"])

class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    remember_me: bool = False

class LoginResponse(BaseModel):
    access_token: str
    token_type: str
    user_id: int
    email: str
    full_name: str
    role: str
    expires_in: int

class EmailOnlyRequest(BaseModel):
    email: EmailStr

class ResetPasswordRequest(BaseModel):
    email: EmailStr
    code: str
    new_password: str = Field(..., min_length=6)


@router.post("/send-signup-code")
async def send_signup_code(payload: EmailOnlyRequest, db: Session = Depends(get_db)):
    return AuthController.send_signup_code(db, str(payload.email))

@router.post("/forgot-password")
async def forgot_password(payload: EmailOnlyRequest, db: Session = Depends(get_db)):
    return AuthController.forgot_password(db, str(payload.email))

@router.post("/reset-password")
async def reset_password(payload: ResetPasswordRequest, db: Session = Depends(get_db)):
    return AuthController.reset_password(db, payload)

@router.post("/signup", status_code=status.HTTP_201_CREATED)
async def signup(
    full_name: str = Form(...),
    email: EmailStr = Form(...),
    phone: str = Form(...),
    password: str = Form(...),
    verification_code: str = Form(...),
    role: str = Form("commuter"),
    license_number: Optional[str] = Form(None),
    license_expiry: Optional[str] = Form(None),
    profile_image: Optional[UploadFile] = File(None),
    cin_image: Optional[UploadFile] = File(None),
    driver_card_image: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
):
    return AuthController.signup(
        db, full_name, str(email), phone, password, verification_code, role,
        license_number, license_expiry, profile_image, cin_image, driver_card_image
    )

@router.post("/login", response_model=LoginResponse)
async def login(login_data: LoginRequest, db: Session = Depends(get_db)):
    return AuthController.login(db, login_data)

@router.get("/me")
async def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise HTTPException(status_code=401, detail="Token invalide")
    except JWTError:
        raise HTTPException(status_code=401, detail="Session expirée ou invalide")
    
    return AuthController.get_me(db, email)
