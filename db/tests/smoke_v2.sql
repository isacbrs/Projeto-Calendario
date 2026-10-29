BEGIN;

-- ============================================================
-- PREPARAÇÃO DOS DADOS DE TESTE
-- ============================================================

DO $$
DECLARE
    v_usuario1 INTEGER;
    v_usuario2 INTEGER;
    v_grupo1 INTEGER;
    v_grupo2 INTEGER;
    v_participacao1 INTEGER;
    v_participacao2 INTEGER;
    v_etiqueta1 INTEGER;
    v_evento1 INTEGER;
    v_notificacao1 INTEGER;
BEGIN
    -- Usuários de teste
    INSERT INTO usuario (nome, email, senha)
    VALUES ('Teste RINT 1', 'rint1@teste.com', 'senha_teste')
    RETURNING id_usuario INTO v_usuario1;

    INSERT INTO usuario (nome, email, senha)
    VALUES ('Teste RINT 2', 'rint2@teste.com', 'senha_teste')
    RETURNING id_usuario INTO v_usuario2;

    -- Grupos de teste
    INSERT INTO grupo (nome, codigo_convite)
    VALUES ('Grupo RINT 1', 'rint_grupo_1')
    RETURNING id_grupo INTO v_grupo1;

    INSERT INTO grupo (nome, codigo_convite)
    VALUES ('Grupo RINT 2', 'rint_grupo_2')
    RETURNING id_grupo INTO v_grupo2;

    -- Participações
    INSERT INTO participacao (id_usuario, id_grupo)
    VALUES (v_usuario1, v_grupo1)
    RETURNING id_participacao INTO v_participacao1;

    INSERT INTO participacao (id_usuario, id_grupo)
    VALUES (v_usuario2, v_grupo1)
    RETURNING id_participacao INTO v_participacao2;

    -- Etiqueta inicial
    INSERT INTO etiqueta (id_grupo, nome, cor)
    VALUES (v_grupo1, 'Prova', '#0000FF')
    RETURNING id_etiqueta INTO v_etiqueta1;

    -- Evento inicial
    INSERT INTO evento (
        id_grupo,
        id_criador,
        id_etiqueta,
        titulo,
        data_evento,
        antecedencia_dias
    )
    VALUES (
        v_grupo1,
        v_usuario1,
        v_etiqueta1,
        'Evento RINT',
        CURRENT_DATE + 5,
        2
    )
    RETURNING id_evento INTO v_evento1;

    -- Notificação inicial
    INSERT INTO notificacao (
        id_evento,
        id_participacao,
        data_hora_prevista,
        estado
    )
    VALUES (
        v_evento1,
        v_participacao1,
        CURRENT_TIMESTAMP + INTERVAL '1 day',
        'PENDENTE'
    )
    RETURNING id_notificacao INTO v_notificacao1;

    RAISE NOTICE 'Preparação concluída: usuários, grupos, participações, etiqueta, evento e notificação criados.';
END $$;


-- ============================================================
-- TESTE 1: UNICIDADE DO NOME DA ETIQUETA POR GRUPO (RINT03)
-- ============================================================

DO $$
DECLARE
    v_grupo1 INTEGER;
    v_grupo2 INTEGER;
BEGIN
    SELECT id_grupo INTO STRICT v_grupo1
    FROM grupo
    WHERE codigo_convite = 'rint_grupo_1';

    SELECT id_grupo INTO STRICT v_grupo2
    FROM grupo
    WHERE codigo_convite = 'rint_grupo_2';

    -- O mesmo nome em grupos diferentes deve ser permitido.
    INSERT INTO etiqueta (id_grupo, nome, cor)
    VALUES (v_grupo2, 'PROVA', '#00FF00');

    RAISE NOTICE 'OK: nome repetido em grupos diferentes foi permitido.';

    -- O mesmo nome, com outra capitalização, no mesmo grupo
    -- deve ser rejeitado.
    BEGIN
        INSERT INTO etiqueta (id_grupo, nome, cor)
        VALUES (v_grupo1, 'PROVA', '#FF0000');

        RAISE EXCEPTION
            'FALHA: nome duplicado no mesmo grupo foi aceito.';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE
                'OK: nome duplicado, ignorando capitalização, foi rejeitado.';
    END;
END $$;


-- ============================================================
-- TESTE 2: ETIQUETA NÃO PODE PERTENCER A OUTRO GRUPO (RINT02)
-- ============================================================

DO $$
DECLARE
    v_grupo1 INTEGER;
    v_grupo2 INTEGER;
    v_etiqueta1 INTEGER;
BEGIN
    SELECT id_grupo INTO STRICT v_grupo1
    FROM grupo
    WHERE codigo_convite = 'rint_grupo_1';

    SELECT id_grupo INTO STRICT v_grupo2
    FROM grupo
    WHERE codigo_convite = 'rint_grupo_2';

    SELECT id_etiqueta INTO STRICT v_etiqueta1
    FROM etiqueta
    WHERE id_grupo = v_grupo1
      AND nome = 'Prova';

    BEGIN
        INSERT INTO evento (
            id_grupo,
            id_etiqueta,
            titulo,
            data_evento,
            antecedencia_dias
        )
        VALUES (
            v_grupo2,
            v_etiqueta1,
            'Evento com etiqueta de outro grupo',
            CURRENT_DATE + 5,
            1
        );

        RAISE EXCEPTION
            'FALHA: evento associado a etiqueta de outro grupo foi aceito.';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE
                'OK: associação entre evento e etiqueta de outro grupo foi rejeitada.';
    END;
END $$;


-- ============================================================
-- TESTE 3: VALIDAÇÃO DOS HORÁRIOS (RINT06)
-- ============================================================

DO $$
DECLARE
    v_grupo INTEGER;
BEGIN
    SELECT id_grupo INTO STRICT v_grupo
    FROM grupo
    WHERE codigo_convite = 'rint_grupo_1';

    -- Término sem início
    BEGIN
        INSERT INTO evento (
            id_grupo,
            titulo,
            data_evento,
            hora_termino,
            antecedencia_dias
        )
        VALUES (
            v_grupo,
            'Evento sem início',
            CURRENT_DATE + 5,
            TIME '10:00',
            1
        );

        RAISE EXCEPTION
            'FALHA: término sem início foi aceito.';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE
                'OK: término sem início foi rejeitado.';
    END;

    -- Término igual ao início
    BEGIN
        INSERT INTO evento (
            id_grupo,
            titulo,
            data_evento,
            hora_inicio,
            hora_termino,
            antecedencia_dias
        )
        VALUES (
            v_grupo,
            'Evento com horários iguais',
            CURRENT_DATE + 5,
            TIME '10:00',
            TIME '10:00',
            1
        );

        RAISE EXCEPTION
            'FALHA: horários iguais foram aceitos.';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE
                'OK: horários iguais foram rejeitados.';
    END;

    -- Término anterior ao início
    BEGIN
        INSERT INTO evento (
            id_grupo,
            titulo,
            data_evento,
            hora_inicio,
            hora_termino,
            antecedencia_dias
        )
        VALUES (
            v_grupo,
            'Evento com término anterior',
            CURRENT_DATE + 5,
            TIME '10:00',
            TIME '09:00',
            1
        );

        RAISE EXCEPTION
            'FALHA: término anterior ao início foi aceito.';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE
                'OK: término anterior ao início foi rejeitado.';
    END;

    -- Início sem término: permitido pelo schema
    INSERT INTO evento (
        id_grupo,
        titulo,
        data_evento,
        hora_inicio,
        antecedencia_dias
    )
    VALUES (
        v_grupo,
        'Evento com início sem término',
        CURRENT_DATE + 5,
        TIME '10:00',
        1
    );

    RAISE NOTICE
        'OK: início sem término foi permitido.';
END $$;


-- ============================================================
-- TESTE 4: VALIDAÇÃO DA ANTECEDÊNCIA (RINT07)
-- ============================================================

DO $$
DECLARE
    v_grupo INTEGER;
    v_dias INTEGER;
BEGIN
    SELECT id_grupo INTO STRICT v_grupo
    FROM grupo
    WHERE codigo_convite = 'rint_grupo_1';

    -- Valores inválidos: 0 e 5
    FOREACH v_dias IN ARRAY ARRAY[0, 5]
    LOOP
        BEGIN
            INSERT INTO evento (
                id_grupo,
                titulo,
                data_evento,
                antecedencia_dias
            )
            VALUES (
                v_grupo,
                'Evento com antecedência inválida',
                CURRENT_DATE + 5,
                v_dias
            );

            RAISE EXCEPTION
                'FALHA: antecedência % foi aceita.', v_dias;
        EXCEPTION
            WHEN check_violation THEN
                RAISE NOTICE
                    'OK: antecedência % foi rejeitada.', v_dias;
        END;
    END LOOP;

    -- Valores válidos: 1 e 4
    INSERT INTO evento (
        id_grupo,
        titulo,
        data_evento,
        antecedencia_dias
    )
    VALUES
        (v_grupo, 'Evento antecedência 1', CURRENT_DATE + 5, 1),
        (v_grupo, 'Evento antecedência 4', CURRENT_DATE + 5, 4);

    RAISE NOTICE
        'OK: antecedência 1 e 4 foram aceitos.';
END $$;


-- ============================================================
-- TESTE 5: EXCLUSÃO DO CRIADOR (RINT01)
-- ============================================================

DO $$
DECLARE
    v_usuario INTEGER;
    v_grupo INTEGER;
    v_evento INTEGER;
    v_criador INTEGER;
BEGIN
    INSERT INTO usuario (nome, email, senha)
    VALUES ('Criador RINT', 'criador_rint@teste.com', 'senha_teste')
    RETURNING id_usuario INTO v_usuario;

    SELECT id_grupo INTO STRICT v_grupo
    FROM grupo
    WHERE codigo_convite = 'rint_grupo_1';

    INSERT INTO evento (
        id_grupo,
        id_criador,
        titulo,
        data_evento,
        antecedencia_dias
    )
    VALUES (
        v_grupo,
        v_usuario,
        'Evento de autoria',
        CURRENT_DATE + 5,
        1
    )
    RETURNING id_evento INTO v_evento;

    DELETE FROM usuario
    WHERE id_usuario = v_usuario;

    SELECT id_criador INTO v_criador
    FROM evento
    WHERE id_evento = v_evento;

    IF FOUND AND v_criador IS NULL THEN
        RAISE NOTICE
            'OK: evento preservado e criador definido como NULL.';
    ELSE
        RAISE EXCEPTION
            'FALHA: exclusão do criador não produziu o resultado esperado.';
    END IF;
END $$;


-- ============================================================
-- TESTE 6: EXCLUSÃO DE GRUPO E CASCATA (RINT)
-- ============================================================

DO $$
DECLARE
    v_grupo INTEGER;
    v_eventos INTEGER;
    v_etiquetas INTEGER;
BEGIN
    INSERT INTO grupo (nome, codigo_convite)
    VALUES ('Grupo para exclusão', 'rint_grupo_exclusao')
    RETURNING id_grupo INTO v_grupo;

    INSERT INTO etiqueta (id_grupo, nome, cor)
    VALUES (v_grupo, 'Etiqueta para exclusão', '#FFFFFF');

    INSERT INTO evento (
        id_grupo,
        titulo,
        data_evento,
        antecedencia_dias
    )
    VALUES (
        v_grupo,
        'Evento para exclusão',
        CURRENT_DATE + 5,
        1
    );

    DELETE FROM grupo
    WHERE id_grupo = v_grupo;

    SELECT COUNT(*) INTO v_eventos
    FROM evento
    WHERE id_grupo = v_grupo;

    SELECT COUNT(*) INTO v_etiquetas
    FROM etiqueta
    WHERE id_grupo = v_grupo;

    IF v_eventos = 0 AND v_etiquetas = 0 THEN
        RAISE NOTICE
            'OK: exclusão do grupo removeu eventos e etiquetas.';
    ELSE
        RAISE EXCEPTION
            'FALHA: registros dependentes sobreviveram à exclusão do grupo.';
    END IF;
END $$;


-- ============================================================
-- TESTE 7: UNICIDADE PARCIAL DE NOTIFICAÇÕES PENDENTES (RINT08)
-- ============================================================

DO $$
DECLARE
    v_evento INTEGER;
    v_participacao INTEGER;
BEGIN
    SELECT id_evento INTO STRICT v_evento
    FROM evento
    WHERE titulo = 'Evento RINT';

    SELECT p.id_participacao INTO STRICT v_participacao
    FROM participacao p
    JOIN grupo g ON g.id_grupo = p.id_grupo
    WHERE g.codigo_convite = 'rint_grupo_1'
    ORDER BY p.id_participacao
    LIMIT 1;

    -- A primeira notificação pendente já foi criada na preparação.
    -- A segunda pendente para o mesmo par deve falhar.
    BEGIN
        INSERT INTO notificacao (
            id_evento,
            id_participacao,
            data_hora_prevista,
            estado
        )
        VALUES (
            v_evento,
            v_participacao,
            CURRENT_TIMESTAMP + INTERVAL '2 days',
            'PENDENTE'
        );

        RAISE EXCEPTION
            'FALHA: segunda notificação pendente para o mesmo par foi aceita.';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE
                'OK: segunda notificação pendente foi rejeitada.';
    END;

    -- Uma notificação ENVIADA para o mesmo par deve ser permitida.
    INSERT INTO notificacao (
        id_evento,
        id_participacao,
        data_hora_prevista,
        estado,
        data_hora_efetiva
    )
    VALUES (
        v_evento,
        v_participacao,
        CURRENT_TIMESTAMP,
        'ENVIADA',
        CURRENT_TIMESTAMP
    );

    RAISE NOTICE
        'OK: notificação ENVIADA para o mesmo par foi permitida.';
END $$;


-- ============================================================
-- TESTE 8: VALIDAÇÃO DO ESTADO DA NOTIFICAÇÃO
-- ============================================================

DO $$
DECLARE
    v_evento INTEGER;
    v_participacao INTEGER;
BEGIN
    SELECT id_evento INTO STRICT v_evento
    FROM evento
    WHERE titulo = 'Evento RINT';

    SELECT p.id_participacao INTO STRICT v_participacao
    FROM participacao p
    JOIN grupo g ON g.id_grupo = p.id_grupo
    WHERE g.codigo_convite = 'rint_grupo_1'
    ORDER BY p.id_participacao
    LIMIT 1;

    BEGIN
        INSERT INTO notificacao (
            id_evento,
            id_participacao,
            data_hora_prevista,
            estado
        )
        VALUES (
            v_evento,
            v_participacao,
            CURRENT_TIMESTAMP + INTERVAL '3 days',
            'INVALIDA'
        );

        RAISE EXCEPTION
            'FALHA: estado inválido de notificação foi aceito.';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE
                'OK: estado inválido de notificação foi rejeitado.';
    END;
END $$;


-- ============================================================
-- TESTE 9: EXCLUSÃO DO EVENTO REMOVE NOTIFICAÇÕES
-- ============================================================

DO $$
DECLARE
    v_evento INTEGER;
    v_notificacoes INTEGER;
BEGIN
    SELECT id_evento INTO STRICT v_evento
    FROM evento
    WHERE titulo = 'Evento RINT';

    DELETE FROM evento
    WHERE id_evento = v_evento;

    SELECT COUNT(*) INTO v_notificacoes
    FROM notificacao
    WHERE id_evento = v_evento;

    IF v_notificacoes = 0 THEN
        RAISE NOTICE
            'OK: exclusão do evento removeu suas notificações.';
    ELSE
        RAISE EXCEPTION
            'FALHA: notificações sobreviveram à exclusão do evento.';
    END IF;
END $$;


-- ============================================================
-- TESTE 10: EXCLUSÃO DA PARTICIPAÇÃO REMOVE NOTIFICAÇÕES
-- ============================================================

DO $$
DECLARE
    v_usuario INTEGER;
    v_grupo INTEGER;
    v_participacao INTEGER;
    v_evento INTEGER;
    v_notificacoes INTEGER;
BEGIN
    SELECT id_grupo INTO STRICT v_grupo
    FROM grupo
    WHERE codigo_convite = 'rint_grupo_1';

    INSERT INTO usuario (nome, email, senha)
    VALUES ('Usuário para exclusão', 'exclusao_participacao@teste.com', 'senha_teste')
    RETURNING id_usuario INTO v_usuario;

    INSERT INTO participacao (id_usuario, id_grupo)
    VALUES (v_usuario, v_grupo)
    RETURNING id_participacao INTO v_participacao;

    INSERT INTO evento (
        id_grupo,
        titulo,
        data_evento,
        antecedencia_dias
    )
    VALUES (
        v_grupo,
        'Evento da participação',
        CURRENT_DATE + 5,
        1
    )
    RETURNING id_evento INTO v_evento;

    INSERT INTO notificacao (
        id_evento,
        id_participacao,
        data_hora_prevista,
        estado
    )
    VALUES (
        v_evento,
        v_participacao,
        CURRENT_TIMESTAMP + INTERVAL '1 day',
        'PENDENTE'
    );

    DELETE FROM participacao
    WHERE id_participacao = v_participacao;

    SELECT COUNT(*) INTO v_notificacoes
    FROM notificacao
    WHERE id_participacao = v_participacao;

    IF v_notificacoes = 0 THEN
        RAISE NOTICE
            'OK: exclusão da participação removeu suas notificações.';
    ELSE
        RAISE EXCEPTION
            'FALHA: notificações sobreviveram à exclusão da participação.';
    END IF;
END $$;

-- ============================================================
-- TESTE: EXCLUSÃO DE ETIQUETA (SET NULL PARCIAL)
-- ============================================================

DO $$
DECLARE
    v_grupo INTEGER;
    v_etiqueta INTEGER;
    v_evento INTEGER;
    v_grupo_evento INTEGER;
    v_etiqueta_evento INTEGER;
BEGIN
    INSERT INTO grupo (nome, codigo_convite)
    VALUES ('Grupo Teste SET NULL', 'rint_setnull')
    RETURNING id_grupo INTO v_grupo;

    INSERT INTO etiqueta (id_grupo, nome, cor)
    VALUES (v_grupo, 'Etiqueta SET NULL', '#123456')
    RETURNING id_etiqueta INTO v_etiqueta;

    INSERT INTO evento (
        id_grupo,
        id_etiqueta,
        titulo,
        data_evento,
        antecedencia_dias
    )
    VALUES (
        v_grupo,
        v_etiqueta,
        'Evento Teste SET NULL',
        CURRENT_DATE + 5,
        1
    )
    RETURNING id_evento INTO v_evento;

    -- Exclui a etiqueta associada ao evento.
    DELETE FROM etiqueta
    WHERE id_etiqueta = v_etiqueta;

    -- Consulta o evento após a exclusão.
    SELECT id_grupo, id_etiqueta
    INTO STRICT v_grupo_evento, v_etiqueta_evento
    FROM evento
    WHERE id_evento = v_evento;

    IF v_grupo_evento = v_grupo
       AND v_etiqueta_evento IS NULL
       AND NOT EXISTS (
           SELECT 1
           FROM etiqueta
           WHERE id_etiqueta = v_etiqueta
       )
    THEN
        RAISE NOTICE
            'OK: etiqueta excluída; evento preservado; id_etiqueta = NULL e id_grupo mantido.';
    ELSE
        RAISE EXCEPTION
            'FALHA: exclusão da etiqueta não preservou corretamente o evento.';
    END IF;
END $$;

-- ============================================================
-- TESTE: EXCLUSÃO DE GRUPO COM EVENTO E ETIQUETA ASSOCIADOS
-- ============================================================

DO $$
DECLARE
    v_grupo INTEGER;
    v_etiqueta INTEGER;
    v_evento INTEGER;
    v_eventos INTEGER;
    v_etiquetas INTEGER;
BEGIN
    INSERT INTO grupo (nome, codigo_convite)
    VALUES ('Grupo para Exclusão em Cascata', 'rint_cascata')
    RETURNING id_grupo INTO v_grupo;

    INSERT INTO etiqueta (id_grupo, nome, cor)
    VALUES (v_grupo, 'Etiqueta em Cascata', '#ABCDEF')
    RETURNING id_etiqueta INTO v_etiqueta;

    INSERT INTO evento (
        id_grupo,
        id_etiqueta,
        titulo,
        data_evento,
        antecedencia_dias
    )
    VALUES (
        v_grupo,
        v_etiqueta,
        'Evento com Etiqueta em Cascata',
        CURRENT_DATE + 5,
        1
    )
    RETURNING id_evento INTO v_evento;

    -- Confirma que o evento está associado à etiqueta.
    IF NOT EXISTS (
        SELECT 1
        FROM evento
        WHERE id_evento = v_evento
          AND id_grupo = v_grupo
          AND id_etiqueta = v_etiqueta
    ) THEN
        RAISE EXCEPTION
            'FALHA: evento não foi associado à etiqueta antes da exclusão.';
    END IF;

    -- Exclui o grupo.
    DELETE FROM grupo
    WHERE id_grupo = v_grupo;

    SELECT COUNT(*) INTO v_eventos
    FROM evento
    WHERE id_evento = v_evento;

    SELECT COUNT(*) INTO v_etiquetas
    FROM etiqueta
    WHERE id_etiqueta = v_etiqueta;

    IF v_eventos = 0 AND v_etiquetas = 0 THEN
        RAISE NOTICE
            'OK: grupo excluído; evento associado à etiqueta e etiqueta foram removidos em cascata.';
    ELSE
        RAISE EXCEPTION
            'FALHA: evento ou etiqueta sobreviveram à exclusão do grupo.';
    END IF;
END $$;


-- ============================================================
-- FINALIZAÇÃO
-- ============================================================

ROLLBACK;