# src/utils/security.py
import os
import bcrypt
import jwt
from datetime import datetime, timedelta, timezone
from dotenv import load_dotenv

load_dotenv()

SECRET_KEY = os.environ.get("JWT_SECRET")
REFRESH_SECRET_KEY = os.environ.get("JWT_REFRESH_SECRET")

def hash_password(senha: str) -> str:
    # Transforma a senha digitada em um código embaralhado (hash)
    salt = bcrypt.gensalt()
    senha_hasheada = bcrypt.hashpw(senha.encode('utf-8'), salt)
    return senha_hasheada.decode('utf-8')

def verify_password(senha_limpa: str, senha_hasheada: str) -> bool:
    # Compara a senha digitada no login com o hash salvo no banco
    return bcrypt.checkpw(senha_limpa.encode('utf-8'), senha_hasheada.encode('utf-8'))

def create_access_token(user_id: str) -> str:
    # Cria o crachá de acesso válido por 30 minutos
    payload = {
        "sub": str(user_id),
        "exp": datetime.now(timezone.utc) + timedelta(minutes=30)
    }
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")

def create_refresh_token(user_id: str) -> str:
    # Cria a chave reserva válida por 30 dias
    payload = {
        "sub": str(user_id),
        "exp": datetime.now(timezone.utc) + timedelta(days=30)
    }
    return jwt.encode(payload, REFRESH_SECRET_KEY, algorithm="HS256")