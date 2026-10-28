# src/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.routes import index, auth # <-- Adicione a importação do auth

app = FastAPI(title="Calendário Acadêmico API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Suas rotas
app.include_router(index.router, prefix="/api", tags=["Teste"])
app.include_router(auth.router, prefix="/api/auth", tags=["Autenticação"]) # <-- Adicione esta linha