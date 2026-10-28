# src/routes/auth.py
from fastapi import APIRouter, HTTPException, status
from src.schemas.user_schema import UserCreate, UserLogin
from src.utils.security import hash_password, verify_password, create_access_token, create_refresh_token
from src.config.db import supabase

router = APIRouter()

@router.post("/registro", status_code=status.HTTP_201_CREATED)
def registrar_usuario(user: UserCreate):
    # 1. Verifica se o e-mail já existe no banco
    response = supabase.table("Usuario").select("*").eq("email", user.email).execute()
    if len(response.data) > 0:
        raise HTTPException(status_code=400, detail="E-mail já cadastrado.")

    # 2. Criptografa a senha
    senha_segura = hash_password(user.senha)

    # 3. Salva no Supabase
    novo_usuario = {
        "nome": user.nome,
        "email": user.email,
        "senha": senha_segura
    }
    supabase.table("Usuario").insert(novo_usuario).execute()
    
    return {"message": "Usuário criado com sucesso!"}


@router.post("/login")
def login(user: UserLogin):
    # 1. Busca o usuário pelo e-mail
    response = supabase.table("Usuario").select("*").eq("email", user.email).execute()
    if len(response.data) == 0:
        raise HTTPException(status_code=401, detail="E-mail ou senha incorretos.")
    
    db_user = response.data[0]

    # 2. Verifica se a senha bate com a do banco
    if not verify_password(user.senha, db_user["senha"]):
        raise HTTPException(status_code=401, detail="E-mail ou senha incorretos.")

    # 3. Gera os tokens
    user_id = db_user["identificador"]
    access_token = create_access_token(user_id)
    refresh_token = create_refresh_token(user_id)

    # 4. Salva o refresh token no banco de dados para gerenciar a sessão
    supabase.table("Usuario").update({"refresh_token": refresh_token}).eq("identificador", user_id).execute()

    # 5. Entrega as chaves para o Front-End
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer"
    }