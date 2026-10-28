-- ==============================================================================
-- Descrição: Testes de aceitação para as regras de integridade e restrições estruturais
-- Banco: PostgreSQL (Nível de Isolamento Padrão: Read Committed)
-- ==============================================================================

\set ON_ERROR_STOP on
BEGIN;

-- ==============================================================================
-- 1. Unicidade de Etiqueta (RINT03)
-- Regra: Mesma cor em grupos diferentes (passa), mesmo grupo com case diferente (falha).
-- ==============================================================================
DO $$
DECLARE 
    g1 INTEGER; g2 INTEGER;
BEGIN
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G1', 'c1') RETURNING id_grupo INTO g1;
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G2', 'c2') RETURNING id_grupo INTO g2;

    -- Inserções válidas em grupos distintos
    INSERT INTO etiqueta (id_grupo, nome, cor) VALUES (g1, 'PROVA', '#0000FF');
    INSERT INTO etiqueta (id_grupo, nome, cor) VALUES (g2, 'Prova', '#00FF00');
    RAISE NOTICE 'OK (Teste 1.1): Etiquetas com nomes idênticos em grupos distintos aceitas.';
    
    -- Violação de unicidade no mesmo grupo (Case-insensitive)
    BEGIN
        INSERT INTO etiqueta (id_grupo, nome, cor) VALUES (g1, 'prova', '#FF0000');
        RAISE EXCEPTION 'FALHA: Unicidade case-insensitive violada sem levantar erro.';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'OK (Teste 1.2): Inserção de "prova" bloqueada por unicidade (RINT03).';
    END;
END $$;   -- ============================================================================== -- 2. Coerência de Escopo - Evento e Etiqueta (RINT02) -- Regra: FK composta impede associar evento a uma etiqueta de outro grupo. -- ============================================================================== DO $$
DECLARE
    g2_id INTEGER; e1_id INTEGER;
BEGIN
    SELECT id_grupo INTO g2_id FROM grupo WHERE codigo_convite = 'c2';
    SELECT id_etiqueta INTO e1_id FROM etiqueta WHERE nome ILIKE 'prova' LIMIT 1;

    BEGIN
        INSERT INTO evento (id_grupo, id_etiqueta, titulo, data_evento, antecedencia_dias)
        VALUES (g2_id, e1_id, 'Evento G2 com Etq G1', current_date + 1, 1);
        RAISE EXCEPTION 'FALHA: Evento inserido com etiqueta de grupo alheio.';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'OK (Teste 2): Associação bloqueada por FK composta (RINT02).';
    END;
END $$;   -- ============================================================================== -- 3. Validação de Horários e Antecedência (RINT06 e RINT07) -- ============================================================================== DO $$
DECLARE
    g_id INTEGER;
BEGIN
    SELECT id_grupo INTO g_id FROM grupo LIMIT 1;
    
    -- Término sem início
    BEGIN
        INSERT INTO evento (id_grupo, titulo, data_evento, hora_termino, antecedencia_dias)
        VALUES (g_id, 'Sem Início', current_date + 1, '10:00', 1);
        RAISE EXCEPTION 'FALHA: Evento aceitou término sem início.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK (Teste 3.1): Evento bloqueado, término exige início (RINT06).';
    END;

    -- Término <= Início
    BEGIN
        INSERT INTO evento (id_grupo, titulo, data_evento, hora_inicio, hora_termino, antecedencia_dias)
        VALUES (g_id, 'Termino Menor', current_date + 1, '10:00', '09:00', 1);
        RAISE EXCEPTION 'FALHA: Evento aceitou término anterior ao início.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK (Teste 3.2): Evento bloqueado, término deve ser maior que início (RINT06).';
    END;

    -- Limites de Antecedência
    BEGIN
        INSERT INTO evento (id_grupo, titulo, data_evento, antecedencia_dias)
        VALUES (g_id, 'Ant 0', current_date + 1, 0);
        RAISE EXCEPTION 'FALHA: Aceitou antecedência = 0.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK (Teste 3.3): Antecedência 0 bloqueada (RINT07).';
    END;
    BEGIN
        INSERT INTO evento (id_grupo, titulo, data_evento, antecedencia_dias)
        VALUES (g_id, 'Ant 5', current_date + 1, 5);
        RAISE EXCEPTION 'FALHA: Aceitou antecedência = 5.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK (Teste 3.4): Antecedência 5 bloqueada (RINT07).';
    END;
END $$;   -- ============================================================================== -- 4. Exclusão do Usuário Criador (RINT01) -- Regra: A exclusão anula a coluna `id_criador`, preservando o evento no grupo. -- ============================================================================== DO $$
DECLARE
    u_id INTEGER; g_id INTEGER; ev_id INTEGER; ev_check evento%ROWTYPE;
BEGIN
    INSERT INTO usuario (nome, email, senha) VALUES ('U_Autor', 'autor@x.com', '123') RETURNING id_usuario INTO u_id;
    SELECT id_grupo INTO g_id FROM grupo LIMIT 1;
    
    INSERT INTO evento (id_grupo, id_criador, titulo, data_evento, antecedencia_dias)
    VALUES (g_id, u_id, 'Evento Autoria', current_date + 1, 1) RETURNING id_evento INTO ev_id;
    
    DELETE FROM usuario WHERE id_usuario = u_id;
    SELECT * INTO ev_check FROM evento WHERE id_evento = ev_id;
    
    IF ev_check.id_evento IS NOT NULL AND ev_check.id_criador IS NULL THEN
        RAISE NOTICE 'OK (Teste 4): Conta excluída e evento preservado com autoria nula (RINT01).';
    ELSE
        RAISE EXCEPTION 'FALHA: Evento foi excluído ou id_criador não foi anulado.';
    END IF;
END $$;   -- ============================================================================== -- 5. Exclusões de Grupo e Cascata Parcial (RN06) -- Regra: Remoção do último membro extingue o grupo. Membros restantes o preservam. -- ============================================================================== DO $$
DECLARE 
    u_del INTEGER; u_stay INTEGER; g_alone INTEGER; g_shared INTEGER;
    v_count_alone INTEGER; v_count_shared INTEGER;
BEGIN
    INSERT INTO usuario (nome, email, senha) VALUES ('U_Del', 'del@x.com', 'x') RETURNING id_usuario INTO u_del;
    INSERT INTO usuario (nome, email, senha) VALUES ('U_Stay', 'stay@x.com', 'x') RETURNING id_usuario INTO u_stay;
    
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_Alone', 'c_alone') RETURNING id_grupo INTO g_alone;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u_del, g_alone);
    
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_Shared', 'c_shared') RETURNING id_grupo INTO g_shared;
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u_del, g_shared);
    INSERT INTO participacao (id_usuario, id_grupo) VALUES (u_stay, g_shared);

    -- Excluir usuário extingue G_Alone (único membro), mas preserva G_Shared (U_Stay permanece)
    DELETE FROM usuario WHERE id_usuario = u_del;
    
    SELECT COUNT(*) INTO v_count_alone FROM grupo WHERE id_grupo = g_alone;
    SELECT COUNT(*) INTO v_count_shared FROM grupo WHERE id_grupo = g_shared;
    
    IF v_count_alone = 0 AND v_count_shared = 1 THEN 
        RAISE NOTICE 'OK (Teste 5): Cascata parcial operou limpo (G_Alone extinto, G_Shared preservado).';
    ELSE 
        RAISE EXCEPTION 'FALHA: Cascata de exclusão não distinguiu o status dos grupos.'; 
    END IF;
END $$;   -- ============================================================================== -- 6. Exclusão de Etiqueta com SET NULL (id_etiqueta) em Evento -- ============================================================================== DO $$
DECLARE 
    g_id INTEGER; etq INTEGER; ev_id INTEGER; ev_check evento%ROWTYPE;
BEGIN
    INSERT INTO grupo (nome, codigo_convite) VALUES ('G_Etq', 'cetq') RETURNING id_grupo INTO g_id;
    INSERT INTO