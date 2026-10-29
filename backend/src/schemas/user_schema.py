# src/schemas/user_schema.py
from pydantic import BaseModel, EmailStr

class UserCreate(BaseModel):
    nome: str
    email: EmailStr
    senha: str

class UserLogin(BaseModel):
    email: EmailStr
    senha: str