from sqlalchemy import Column, Integer, String, Boolean, DateTime
from app.database.connection import Base


class EmailVerificationCode(Base):
    """Codes à usage unique pour inscription et réinitialisation du mot de passe."""

    __tablename__ = "email_verification_codes"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, nullable=False, index=True)
    code_hash = Column(String, nullable=False)
    purpose = Column(String, nullable=False)  # "signup" | "password_reset"
    expires_at = Column(DateTime, nullable=False)
    used = Column(Boolean, default=False, nullable=False)
