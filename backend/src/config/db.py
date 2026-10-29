import os
from dotenv import load_dotenv
from supabase import create_client, Client

# Carrega as variáveis do arquivo .env
load_dotenv()

url: str = os.environ.get("SUPABASE_URL")
key: str = os.environ.get("SUPABASE_KEY")

# Inicializa o cliente do Supabase
supabase: Client = create_client(url, key)