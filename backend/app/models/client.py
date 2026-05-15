from sqlalchemy import Column, Integer, ForeignKey
from .user import User

class Client(User):
    __tablename__ = "clients"
    client_id = Column(Integer, ForeignKey("users.user_id"), primary_key=True)