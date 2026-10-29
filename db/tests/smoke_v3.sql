-- smoke_v3.sql: testes do V3 (RN06, RINT05, imutabilidade de id_grupo).
-- Rodar com o esquema V1..V3 aplicado:
--   cmd /c "docker compose exec -T db psql -U isaquecollab -d calengroup < db\tests\smoke_v3.sql"
-- Cada bloco cria os proprios dados (codigos unicos) e nao depende dos outros.
-- Nada fica gravado: tudo termina em ROLLBACK.
-- Os testes de concorrencia (dois terminais) estao em smoke_v3_concorrencia.md.

\set ON_ERROR_STOP on
BEGIN;

-- ---------------------------------------------------------------------------
-- 1. RN06: sair o unico membro extingue o grupo
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    u INTEGER; g INTEGER; n INTEGER;
BEGIN
    INSERT INTO usuario (nome, email, senha) VALUES ('T1', 't1@x.com', 'x') RETURNING id_usuario INTO u;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T1', 'c_t1') RETURNING id_grupo INTO g;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u, g);

    DELETE FROM participacao WHERE id_usuario = u AND id_grupo = g;

    SELECT COUNT(*) INTO n FROM grupo WHERE id_grupo = g;
    IF n = 0 THEN
        RAISE NOTICE 'OK (1): grupo extinto ao sair o unico membro (RN06).';
    ELSE
        RAISE EXCEPTION 'FALHA (1): grupo sobreviveu sem membros.';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. RN06: sair um membro com outros restantes preserva o grupo
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    u1 INTEGER; u2 INTEGER; g INTEGER; n INTEGER;
BEGIN
    INSERT INTO usuario (nome, email, senha) VALUES ('T2a', 't2a@x.com', 'x') RETURNING id_usuario INTO u1;
    INSERT INTO usuario (nome, email, senha) VALUES ('T2b', 't2b@x.com', 'x') RETURNING id_usuario INTO u2;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T2', 'c_t2') RETURNING id_grupo INTO g;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u1, g), (u2, g);

    DELETE FROM participacao WHERE id_usuario = u1 AND id_grupo = g;

    SELECT COUNT(*) INTO n FROM grupo WHERE id_grupo = g;
    IF n = 1 THEN
        RAISE NOTICE 'OK (2): grupo preservado, ainda ha membro (RN06).';
    ELSE
        RAISE EXCEPTION 'FALHA (2): grupo apagado com membros restantes.';
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. RN06: excluir usuario que e o ultimo de um grupo e membro de outro
--    grupo que continua com gente: so o primeiro grupo some
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    u_del INTEGER; u_stay INTEGER; g_alone INTEGER; g_shared INTEGER;
    n_alone INTEGER; n_shared INTEGER;
BEGIN
    INSERT INTO usuario (nome, email, senha) VALUES ('T3del', 't3del@x.com', 'x') RETURNING id_usuario INTO u_del;
    INSERT INTO usuario (nome, email, senha) VALUES ('T3stay', 't3stay@x.com', 'x') RETURNING id_usuario INTO u_stay;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T3_alone', 'c_t3a') RETURNING id_grupo INTO g_alone;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T3_shared', 'c_t3s') RETURNING id_grupo INTO g_shared;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u_del, g_alone), (u_del, g_shared), (u_stay, g_shared);

    DELETE FROM usuario WHERE id_usuario = u_del;

    SELECT COUNT(*) INTO n_alone FROM grupo WHERE id_grupo = g_alone;
    SELECT COUNT(*) INTO n_shared FROM grupo WHERE id_grupo = g_shared;
    IF n_alone = 0 AND n_shared = 1 THEN
        RAISE NOTICE 'OK (3): so o grupo sem outros membros foi extinto.';
    ELSE
        RAISE EXCEPTION 'FALHA (3): alone=%, shared=% (esperado 0 e 1).', n_alone, n_shared;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. Exclusao direta de grupo com tudo pendurado: participacao, etiqueta,
--    evento COM etiqueta e notificacao. Exercita juntos a cascata, o
--    SET NULL (id_etiqueta) e o trigger do RN06.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    u INTEGER; g INTEGER; p INTEGER; etq INTEGER; ev INTEGER;
    n_part INTEGER; n_etq INTEGER; n_ev INTEGER; n_not INTEGER;
BEGIN
    INSERT INTO usuario (nome, email, senha) VALUES ('T4', 't4@x.com', 'x') RETURNING id_usuario INTO u;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T4', 'c_t4') RETURNING id_grupo INTO g;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u, g) RETURNING id_participacao INTO p;
    INSERT INTO etiqueta (id_grupo, nome, cor) VALUES (g, 'Tag T4', '#112233') RETURNING id_etiqueta INTO etq;
    INSERT INTO evento (id_grupo, id_etiqueta, titulo, data_evento, antecedencia_dias)
        VALUES (g, etq, 'Ev T4', current_date + 1, 1) RETURNING id_evento INTO ev;
    INSERT INTO notificacao (id_evento, id_participacao, data_hora_prevista, estado)
        VALUES (ev, p, now() + interval '1 day', 'PENDENTE');

    DELETE FROM grupo WHERE id_grupo = g;

    SELECT COUNT(*) INTO n_part FROM participacao WHERE id_grupo = g;
    SELECT COUNT(*) INTO n_etq FROM etiqueta WHERE id_grupo = g;
    SELECT COUNT(*) INTO n_ev FROM evento WHERE id_grupo = g;
    SELECT COUNT(*) INTO n_not FROM notificacao WHERE id_evento = ev;
    IF n_part + n_etq + n_ev + n_not = 0 THEN
        RAISE NOTICE 'OK (4): exclusao direta do grupo limpou as quatro tabelas, sem erro nem recursao.';
    ELSE
        RAISE EXCEPTION 'FALHA (4): sobraram part=%, etq=%, ev=%, not=%.', n_part, n_etq, n_ev, n_not;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 5. RINT05 no INSERT: evento de um grupo, participacao de outro
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    u1 INTEGER; u2 INTEGER; g1 INTEGER; g2 INTEGER; p1 INTEGER; p2 INTEGER; ev INTEGER;
BEGIN
    INSERT INTO usuario (nome, email, senha) VALUES ('T5a', 't5a@x.com', 'x') RETURNING id_usuario INTO u1;
    INSERT INTO usuario (nome, email, senha) VALUES ('T5b', 't5b@x.com', 'x') RETURNING id_usuario INTO u2;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T5a', 'c_t5a') RETURNING id_grupo INTO g1;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T5b', 'c_t5b') RETURNING id_grupo INTO g2;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u1, g1) RETURNING id_participacao INTO p1;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u2, g2) RETURNING id_participacao INTO p2;
    INSERT INTO evento (id_grupo, titulo, data_evento, antecedencia_dias)
        VALUES (g1, 'Ev T5', current_date + 1, 1) RETURNING id_evento INTO ev;

    BEGIN
        INSERT INTO notificacao (id_evento, id_participacao, data_hora_prevista, estado)
            VALUES (ev, p2, now(), 'PENDENTE');
        RAISE EXCEPTION 'FALHA (5): notificacao cruzando grupos foi aceita.';
    EXCEPTION WHEN SQLSTATE '23R05' THEN
        RAISE NOTICE 'OK (5a): INSERT cruzando grupos bloqueado (RINT05, 23R05).';
    END;

    INSERT INTO notificacao (id_evento, id_participacao, data_hora_prevista, estado)
        VALUES (ev, p1, now(), 'PENDENTE');
    RAISE NOTICE 'OK (5b): INSERT consistente, mesmo grupo, aceito.';
END $$;

-- ---------------------------------------------------------------------------
-- 6. RINT05 no UPDATE: tanto id_participacao quanto id_evento
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    u1 INTEGER; u2 INTEGER; g1 INTEGER; g2 INTEGER; p1 INTEGER; p2 INTEGER;
    ev1 INTEGER; ev2 INTEGER; nt INTEGER;
BEGIN
    INSERT INTO usuario (nome, email, senha) VALUES ('T6a', 't6a@x.com', 'x') RETURNING id_usuario INTO u1;
    INSERT INTO usuario (nome, email, senha) VALUES ('T6b', 't6b@x.com', 'x') RETURNING id_usuario INTO u2;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T6a', 'c_t6a') RETURNING id_grupo INTO g1;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T6b', 'c_t6b') RETURNING id_grupo INTO g2;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u1, g1) RETURNING id_participacao INTO p1;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u2, g2) RETURNING id_participacao INTO p2;
    INSERT INTO evento (id_grupo, titulo, data_evento, antecedencia_dias)
        VALUES (g1, 'Ev T6a', current_date + 1, 1) RETURNING id_evento INTO ev1;
    INSERT INTO evento (id_grupo, titulo, data_evento, antecedencia_dias)
        VALUES (g2, 'Ev T6b', current_date + 1, 1) RETURNING id_evento INTO ev2;
    INSERT INTO notificacao (id_evento, id_participacao, data_hora_prevista, estado)
        VALUES (ev1, p1, now(), 'PENDENTE') RETURNING id_notificacao INTO nt;

    BEGIN
        UPDATE notificacao SET id_participacao = p2 WHERE id_notificacao = nt;
        RAISE EXCEPTION 'FALHA (6a): UPDATE de id_participacao cruzando grupos foi aceito.';
    EXCEPTION WHEN SQLSTATE '23R05' THEN
        RAISE NOTICE 'OK (6a): UPDATE de id_participacao bloqueado (RINT05).';
    END;

    BEGIN
        UPDATE notificacao SET id_evento = ev2 WHERE id_notificacao = nt;
        RAISE EXCEPTION 'FALHA (6b): UPDATE de id_evento cruzando grupos foi aceito.';
    EXCEPTION WHEN SQLSTATE '23R05' THEN
        RAISE NOTICE 'OK (6b): UPDATE de id_evento bloqueado (RINT05).';
    END;
END $$;

-- ---------------------------------------------------------------------------
-- 7. RINT05 com referencia inexistente: quem responde e a FK (23503),
--    nao o trigger. O backend nao deve ver isso como violacao de regra.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    u INTEGER; g INTEGER; p INTEGER; ev INTEGER;
BEGIN
    INSERT INTO usuario (nome, email, senha) VALUES ('T7', 't7@x.com', 'x') RETURNING id_usuario INTO u;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T7', 'c_t7') RETURNING id_grupo INTO g;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u, g) RETURNING id_participacao INTO p;
    INSERT INTO evento (id_grupo, titulo, data_evento, antecedencia_dias)
        VALUES (g, 'Ev T7', current_date + 1, 1) RETURNING id_evento INTO ev;

    BEGIN
        INSERT INTO notificacao (id_evento, id_participacao, data_hora_prevista, estado)
            VALUES (999999999, p, now(), 'PENDENTE');
        RAISE EXCEPTION 'FALHA (7a): id_evento inexistente foi aceito.';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'OK (7a): id_evento inexistente rejeitado pela FK (23503).';
    END;

    BEGIN
        INSERT INTO notificacao (id_evento, id_participacao, data_hora_prevista, estado)
            VALUES (ev, 999999999, now(), 'PENDENTE');
        RAISE EXCEPTION 'FALHA (7b): id_participacao inexistente foi aceito.';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'OK (7b): id_participacao inexistente rejeitado pela FK (23503).';
    END;
END $$;

-- ---------------------------------------------------------------------------
-- 8. Imutabilidade de id_grupo em evento, participacao e etiqueta.
--    O usuario NAO participa do grupo de destino, entao sem o trigger o
--    UPDATE seria aceito: o teste prova o trigger, nao outra constraint.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    u INTEGER; g1 INTEGER; g2 INTEGER; p INTEGER; etq INTEGER; ev INTEGER;
    v_constraint TEXT;
BEGIN
    INSERT INTO usuario (nome, email, senha) VALUES ('T8', 't8@x.com', 'x') RETURNING id_usuario INTO u;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T8a', 'c_t8a') RETURNING id_grupo INTO g1;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_T8b', 'c_t8b') RETURNING id_grupo INTO g2;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u, g1) RETURNING id_participacao INTO p;
    INSERT INTO etiqueta (id_grupo, nome, cor) VALUES (g1, 'Tag T8', '#445566') RETURNING id_etiqueta INTO etq;
    INSERT INTO evento (id_grupo, titulo, data_evento, antecedencia_dias)
        VALUES (g1, 'Ev T8', current_date + 1, 1) RETURNING id_evento INTO ev;

    BEGIN
        UPDATE participacao SET id_grupo = g2 WHERE id_participacao = p;
        RAISE EXCEPTION 'FALHA (8a): participacao mudou de grupo.';
    EXCEPTION WHEN SQLSTATE '23R01' THEN
        RAISE NOTICE 'OK (8a): participacao.id_grupo imutavel (23R01).';
    END;

    BEGIN
        UPDATE etiqueta SET id_grupo = g2 WHERE id_etiqueta = etq;
        RAISE EXCEPTION 'FALHA (8b): etiqueta mudou de grupo.';
    EXCEPTION WHEN SQLSTATE '23R01' THEN
        RAISE NOTICE 'OK (8b): etiqueta.id_grupo imutavel (23R01).';
    END;

    BEGIN
        UPDATE evento SET id_grupo = g2 WHERE id_evento = ev;
        RAISE EXCEPTION 'FALHA (8c): evento mudou de grupo.';
    EXCEPTION WHEN SQLSTATE '23R01' THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        RAISE NOTICE 'OK (8c): evento.id_grupo imutavel (23R01), constraint = %.', v_constraint;
    END;

    -- Regravar o mesmo valor nao e mudanca e deve passar.
    UPDATE evento SET id_grupo = g1 WHERE id_evento = ev;
    RAISE NOTICE 'OK (8d): UPDATE com o mesmo id_grupo aceito.';
END $$;

ROLLBACK;