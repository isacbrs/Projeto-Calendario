-- V3: regras de integridade que o esquema declarativo nao expressa.
--   Imutabilidade do grupo (fecha as brechas de RINT02 e RINT05 por UPDATE)
--   RN06  - a saida da ultima participacao extingue o grupo
--   RINT05 - evento e participacao de uma notificacao pertencem ao mesmo grupo
--
-- SQLSTATE usados (todos na classe 23, que os drivers Python costumam mapear
-- para IntegrityError). O backend distingue as regras pelo SQLSTATE ou pelo
-- nome da constraint (diag.constraint_name), nunca pelo texto da mensagem:
--   23R01  imutabilidade de id_grupo   (constraint imutavel_<tabela>_id_grupo)
--   23R05  RINT05                      (constraint rint05_escopo_notificacao)

-- ---------------------------------------------------------------------------
-- Imutabilidade: id_grupo nunca muda depois da criacao do registro.
-- Sem isso, UPDATE evento/participacao/etiqueta SET id_grupo violaria
-- RINT02 e RINT05 sem que nenhum trigger ou FK percebesse.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_imutabilidade_grupo() RETURNS TRIGGER AS $fn$
BEGIN
    IF NEW.id_grupo IS DISTINCT FROM OLD.id_grupo THEN
        RAISE EXCEPTION 'id_grupo de % nao pode ser alterado', TG_TABLE_NAME
            USING ERRCODE = '23R01',
                  TABLE = TG_TABLE_NAME,
                  CONSTRAINT = 'imutavel_' || TG_TABLE_NAME || '_id_grupo';
    END IF;
    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

CREATE TRIGGER trg_evento_imutabilidade
BEFORE UPDATE OF id_grupo ON evento
FOR EACH ROW EXECUTE FUNCTION fn_imutabilidade_grupo();

CREATE TRIGGER trg_participacao_imutabilidade
BEFORE UPDATE OF id_grupo ON participacao
FOR EACH ROW EXECUTE FUNCTION fn_imutabilidade_grupo();

CREATE TRIGGER trg_etiqueta_imutabilidade
BEFORE UPDATE OF id_grupo ON etiqueta
FOR EACH ROW EXECUTE FUNCTION fn_imutabilidade_grupo();

-- ---------------------------------------------------------------------------
-- RN06: remover a ultima participacao extingue o grupo.
--
-- FOR UPDATE: trava a linha do grupo para serializar saidas simultaneas.
-- Sem a trava, duas transacoes que removem os dois ultimos membros enxergam
-- cada uma "ainda existe o outro" e o grupo sobrevive vazio.
--
-- IF FOUND: quando o proprio grupo esta sendo apagado (DELETE FROM grupo,
-- cascata para participacao), a linha do grupo ja nao e visivel e o PERFORM
-- nao encontra nada. Sem a guarda, o DELETE seguinte afetaria 0 linhas; ela
-- deixa explicito que nada deve ser feito nesse caso. Nao ha recursao.
--
-- Risco conhecido: dois usuarios que compartilham mais de um grupo, excluidos
-- ao mesmo tempo, podem travar os grupos em ordens opostas. O Postgres aborta
-- uma das transacoes com SQLSTATE 40P01 (deadlock). O backend deve repetir a
-- operacao quando receber esse erro.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_extingue_grupo_vazio() RETURNS TRIGGER AS $fn$
DECLARE
    v_qtd_membros INTEGER;
BEGIN
    PERFORM 1 FROM grupo WHERE id_grupo = OLD.id_grupo FOR UPDATE;

    IF FOUND THEN
        SELECT COUNT(*) INTO v_qtd_membros
        FROM participacao
        WHERE id_grupo = OLD.id_grupo;

        IF v_qtd_membros = 0 THEN
            DELETE FROM grupo WHERE id_grupo = OLD.id_grupo;
        END IF;
    END IF;

    RETURN OLD;
END;
$fn$ LANGUAGE plpgsql;

CREATE TRIGGER trg_extingue_grupo_vazio
AFTER DELETE ON participacao
FOR EACH ROW
EXECUTE FUNCTION fn_extingue_grupo_vazio();

-- ---------------------------------------------------------------------------
-- RINT05: o evento e a participacao destinataria de uma notificacao devem
-- pertencer ao mesmo grupo.
--
-- Se evento ou participacao nao existe, a funcao nao decide nada: a FK da
-- propria tabela reporta o erro (23503). Assim uma referencia inexistente nao
-- e confundida com uma violacao da regra de negocio.
-- Como id_grupo e imutavel em evento e participacao, a checagem feita aqui
-- continua valida pelo resto da vida da notificacao.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_valida_escopo_notificacao() RETURNS TRIGGER AS $fn$
DECLARE
    v_grupo_evento INTEGER;
    v_grupo_participacao INTEGER;
BEGIN
    SELECT id_grupo INTO v_grupo_evento
    FROM evento WHERE id_evento = NEW.id_evento;

    SELECT id_grupo INTO v_grupo_participacao
    FROM participacao WHERE id_participacao = NEW.id_participacao;

    IF v_grupo_evento IS NULL OR v_grupo_participacao IS NULL THEN
        RETURN NEW;
    END IF;

    IF v_grupo_evento <> v_grupo_participacao THEN
        RAISE EXCEPTION 'evento e participacao destinataria pertencem a grupos diferentes'
            USING ERRCODE = '23R05',
                  TABLE = 'notificacao',
                  CONSTRAINT = 'rint05_escopo_notificacao';
    END IF;

    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

CREATE TRIGGER trg_valida_escopo_notificacao
BEFORE INSERT OR UPDATE OF id_evento, id_participacao ON notificacao
FOR EACH ROW
EXECUTE FUNCTION fn_valida_escopo_notificacao();