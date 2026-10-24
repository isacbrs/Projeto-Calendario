from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.routes import index

app = FastAPI(title="Calendário Acadêmico API")

# Configuração de CORS (Permite que o Front-End acesse a API sem bloqueios)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Adicionando as rotas ao servidor
app.include_router(index.router, prefix="/api")