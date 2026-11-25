DROP VIEW IF EXISTS vw_cronograma_partidas, vw_painel_principal CASCADE;
DROP FUNCTION IF EXISTS fn_buscar_jogadores(VARCHAR), fn_validar_partida(), fn_registrar_log_partida() CASCADE;
DROP TABLE IF EXISTS historico_partidas, partidas, modalidades, jogadores CASCADE;

CREATE TABLE jogadores (
    id_jogador SERIAL PRIMARY KEY,
    nickname VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    senha VARCHAR(100) NOT NULL,
    status_conta VARCHAR(20) NOT NULL DEFAULT 'ATIVO',
    data_cadastro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_status_conta CHECK (status_conta IN ('ATIVO', 'INATIVO', 'BANIDO'))
);

CREATE TABLE modalidades (
    id_modalidade SERIAL PRIMARY KEY,
    nome_modalidade VARCHAR(80) NOT NULL UNIQUE,
    genero VARCHAR(50) NOT NULL,
    descricao TEXT NOT NULL
);

CREATE TABLE partidas (
    id_partida SERIAL PRIMARY KEY,
    id_jogador INT NOT NULL,
    id_modalidade INT NOT NULL,
    titulo VARCHAR(150) NOT NULL,
    data_partida TIMESTAMP NOT NULL,
    status_partida VARCHAR(30) NOT NULL DEFAULT 'AGENDADA',
    data_criacao TIMESTAMP,
    CONSTRAINT fk_partida_jogador FOREIGN KEY (id_jogador) 
        REFERENCES jogadores(id_jogador) ON DELETE RESTRICT,
    CONSTRAINT fk_partida_modalidade FOREIGN KEY (id_modalidade) 
        REFERENCES modalidades(id_modalidade) ON DELETE RESTRICT,
    CONSTRAINT chk_status_partida CHECK (status_partida IN ('AGENDADA', 'EM_ANDAMENTO', 'FINALIZADA', 'CANCELADA'))
);

CREATE TABLE historico_partidas (
    id_historico SERIAL PRIMARY KEY,
    id_partida INT NOT NULL,
    acao VARCHAR(50) NOT NULL,
    detalhes TEXT NOT NULL,
    data_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_historico_partida FOREIGN KEY (id_partida) 
        REFERENCES partidas(id_partida) ON DELETE CASCADE
);

CREATE OR REPLACE FUNCTION fn_validar_partida()
RETURNS TRIGGER AS $$
DECLARE
    v_status VARCHAR(20);
    v_nick VARCHAR(50);
BEGIN
    SELECT status_conta, nickname 
    INTO v_status, v_nick
    FROM jogadores 
    WHERE id_jogador = NEW.id_jogador;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Jogador ID % não existe.', NEW.id_jogador;
    END IF;

    IF v_status <> 'ATIVO' THEN
        RAISE EXCEPTION 'Bloqueado: O jogador % está com status % e não pode jogar.', v_nick, v_status;
    END IF;

    NEW.data_criacao := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_partida
BEFORE INSERT ON partidas
FOR EACH ROW
EXECUTE FUNCTION fn_validar_partida();

CREATE OR REPLACE FUNCTION fn_registrar_log_partida()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO historico_partidas (id_partida, acao, detalhes, data_registro)
    VALUES (
        NEW.id_partida,
        'NOVA_PARTIDA',
        'Partida "' || NEW.titulo || '" cadastrada para o jogador ID ' || NEW.id_jogador,
        CURRENT_TIMESTAMP
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_registrar_log_partida
AFTER INSERT ON partidas
FOR EACH ROW
EXECUTE FUNCTION fn_registrar_log_partida();

CREATE OR REPLACE FUNCTION fn_buscar_jogadores(p_termo VARCHAR)
RETURNS TABLE (
    id_jogador INT,
    nickname VARCHAR,
    email VARCHAR,
    status_conta VARCHAR,
    data_cadastro TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        j.id_jogador,
        j.nickname,
        j.email,
        j.status_conta,
        j.data_cadastro
    FROM jogadores j
    WHERE j.nickname ILIKE '%' || p_termo || '%'
       OR j.email ILIKE '%' || p_termo || '%'
    ORDER BY j.nickname ASC;
END;
$$ LANGUAGE plpgsql;

INSERT INTO jogadores (nickname, email, senha, status_conta) VALUES
('FalleN_BR', 'fallen@esports.com.br', 'senha123', 'ATIVO'),
('Aspas_Aim', 'aspas@valorantpro.com', 'aimbot2026', 'ATIVO'),
('brTT_Pai', 'brtt@cblol.com.br', 'rexpeita99', 'ATIVO'),
('ToxicPlayer99', 'toxic@banido.com', '123456', 'BANIDO');

INSERT INTO modalidades (nome_modalidade, genero, descricao) VALUES
('Counter-Strike 2', 'FPS Tático', 'Competição 5v5 em mapas competitivos.'),
('Valorant', 'FPS Tático', 'Partidas competitivas 5v5 com agentes.'),
('League of Legends', 'MOBA', 'Batalha estratégica 5v5 na arena.');

INSERT INTO partidas (id_jogador, id_modalidade, titulo, data_partida, status_partida) VALUES
(1, 1, 'Final Major - FURIA vs NAVI', CURRENT_TIMESTAMP + INTERVAL '5 days', 'AGENDADA'),
(2, 2, 'Semifinal Masters - LOUD vs Sentinels', CURRENT_TIMESTAMP + INTERVAL '2 days', 'AGENDADA'),
(3, 3, 'Abertura CBLOL - Pain vs Red Canids', CURRENT_TIMESTAMP + INTERVAL '12 days', 'AGENDADA');

CREATE OR REPLACE VIEW vw_painel_principal AS
SELECT 
    j.nickname AS jogador_nickname,
    p.titulo AS titulo_partida,
    m.nome_modalidade AS modalidade,
    p.data_partida,
    p.status_partida AS status_disputa
FROM partidas p
INNER JOIN jogadores j ON p.id_jogador = j.id_jogador
INNER JOIN modalidades m ON p.id_modalidade = m.id_modalidade;

CREATE OR REPLACE VIEW vw_cronograma_partidas AS
SELECT 
    p.id_partida,
    p.titulo AS titulo_partida,
    p.data_partida,
    p.status_partida,
    GREATEST(0, EXTRACT(DAY FROM (p.data_partida - CURRENT_TIMESTAMP))::INT) AS dias_restantes,
    j.nickname AS jogador_responsavel
FROM partidas p
INNER JOIN jogadores j ON p.id_jogador = j.id_jogador
