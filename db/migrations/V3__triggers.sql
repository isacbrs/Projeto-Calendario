-- Mecanismo único de imutabilidade: Impede a migração de registros entre grupos, 
-- selando as brechas lógicas de RINT02 e RINT05 após a criação.
CREATE OR REPLACE FUNCTION fn_imutabilidade_grupo() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.id_grupo IS DISTINCT FROM OLD.id_grupo THEN
        RAISE EXCEPTION 'Imutabilidade: A restrição de negócio proíbe a migração do registro para outro grupo.' 
        USING ERRCODE = '23000';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_evento_imutabilidade 
BEFORE UPDATE OF id_grupo ON evento 
FOR EACH ROW EXECUTE FUNCTION fn_imutabilidade_grupo();

CREATE TRIGGER trg_participacao_imutabilidade 
BEFORE UPDATE OF id_grupo ON participacao 
FOR EACH ROW EXECUTE FUNCTION fn_imutabilidade_grupo();

CREATE TRIGGER trg_etiqueta_imutabilidade 
BEFORE UPDATE OF id_grupo ON etiqueta 
FOR EACH ROW EXECUTE FUNCTION fn_imutabilidade_grupo();

-- Trigger para RN06: Extinção automática do grupo
CREATE OR REPLACE FUNCTION fn_extingue_grupo_vazio() RETURNS TRIGGER AS $$
DECLARE
    v_qtd_membros INTEGER;
BEGIN
    -- Limitação Conhecida (Concorrência): O FOR UPDATE serializa saídas simultâneas,
    -- mas pode causar lentidão se houver contenção pesada de lock no grupo.
    -- O bloco IF FOUND é defensivo para proteger a transação de loops na cascata direta.
    PERFORM 1 FROM grupo WHERE id_grupo = OLD.id_grupo FOR UPDATE;

    IF FOUND THEN
        SELECT COUNT(*) INTO v_qtd_membros FROM participacao WHERE id_grupo = OLD.id_grupo;
        IF v_qtd_membros = 0 THEN
            DELETE FROM grupo WHERE id_grupo = OLD.id_grupo;
        END IF;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_extingue_grupo_vazio
AFTER DELETE ON participacao
FOR EACH ROW
EXECUTE FUNCTION fn_extingue_grupo_vazio();

-- Trigger para RINT05: Coerência de escopo da notificação
CREATE OR REPLACE FUNCTION fn_valida_escopo_notificacao() RETURNS TRIGGER AS $$
DECLARE
    v_grupo_evento INTEGER;
    v_grupo_participacao INTEGER;
BEGIN
    SELECT id_grupo INTO v_grupo_evento FROM evento WHERE id_evento = NEW.id_evento;
    SELECT id_grupo INTO v_grupo_participacao FROM participacao WHERE id_participacao = NEW.id_participacao;

    -- O operador IS DISTINCT FROM captura adequadamente as comparações com NULL
    IF v_grupo_evento IS DISTINCT FROM v_grupo_participacao THEN
        -- Utiliza a classe 23 (Integrity Constraint Violation) para mapeamento limpo no backend
        RAISE EXCEPTION 'RINT05: Evento e participação destinatária divergem no grupo.' 
        USING ERRCODE = '23000';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_valida_escopo_notificacao
BEFORE INSERT OR UPDATE OF id_evento, id_participacao ON notificacao
FOR EACH ROW
EXECUTE FUNCTION fn_valida_escopo_notificacao();