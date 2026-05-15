from pydantic import BaseModel, EmailStr
from typing import Optional
from app.models.base_enums import UserRoleEnum

class UserCreate(BaseModel):
    full_name: str
    email: EmailStr
    phone: Optional[str]
    password: str
    role: UserRoleEnum

class UserResponse(BaseModel):
    user_id: int
    full_name: str
    email: EmailStr
    phone: Optional[str]
    role: UserRoleEnum
    is_active: bool
    image_url: Optional[str]

    class Config:
        from_attributes = True