from fastapi import APIRouter

router = APIRouter()

@router.get("/")
def teste_api():
    return {"message": "API do Calendário Acadêmico operando com sucesso em Python!"}