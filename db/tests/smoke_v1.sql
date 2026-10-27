BEGIN;

INSERT INTO usuario (nome, email, senha) VALUES ('Ana', 'Ana@x.com', 'x');
INSERT INTO grupo (nome, codigo_convite) VALUES ('G1', 'c1');
INSERT INTO participacao (id_usuario, id_grupo)
  SELECT id_usuario, id_grupo FROM usuario, grupo;

DO $$ BEGIN
  INSERT INTO participacao (id_usuario, id_grupo)
    SELECT id_usuario, id_grupo FROM usuario, grupo;
  RAISE EXCEPTION 'FALHA: participação duplicada foi aceita';
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'OK: duplicata bloqueada -> %', SQLERRM;
END $$;

DO $$ BEGIN
  INSERT INTO usuario (nome, email, senha) VALUES ('Outra', 'ANA@x.com', 'x');
  RAISE EXCEPTION 'FALHA: e-mail com caixa diferente foi aceito';
EXCEPTION WHEN unique_violation THEN
  RAISE NOTICE 'OK: e-mail case-insensitive -> %', SQLERRM;
END $$;

SELECT count(*) AS participacoes_antes FROM participacao;
DELETE FROM usuario WHERE email = 'Ana@x.com';
SELECT count(*) AS participacoes_depois FROM participacao;

ROLLBACK;