-- Seminário Banco de Dados II (BAN2002) - UDESC
-- TimescaleDB: Gerenciamento de Séries Temporais no PostgreSQL
-- Kelwin Efrain Bagnhuk da Silva e Uriel Pacheco de Souza
--
-- Cenário: 10 sensores, 1 leitura por minuto, 30 dias (~432 mil linhas)
--
-- Consultas avaliadas:
--   1. Media da ultima hora               (dados recentes)
--   2. Media horaria dos ultimos 7 dias   (dados recentes)
--   3. Media diaria entre 30 e 14 dias atras (dados antigos, dentro da zona de compressao)

-- ============================================================
-- DEMONSTRAÇÃO 1: HYPERTABLE E INSERÇÃO
-- ============================================================

-- 1. Habilita a extensão no banco
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Mostra a versão instalada
SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';

-- 2. Cria a tabela de leituras
CREATE TABLE sensor_data (
    time        TIMESTAMPTZ      NOT NULL,
    sensor_id   INTEGER          NOT NULL,
    temperatura DOUBLE PRECISION,
    umidade     DOUBLE PRECISION
);

-- Converte em hypertable particionada por time (chunks de 7 dias)
SELECT create_hypertable('sensor_data', by_range('time'));

-- 3. Insere uma leitura por minuto de cada sensor nos últimos 30 dias
INSERT INTO sensor_data (time, sensor_id, temperatura, umidade)
SELECT
    t,
    s,
    20 + random() * 10,
    50 + random() * 30
FROM generate_series(now() - interval '30 days', now(), interval '1 minute') AS t,
     generate_series(1, 10) AS s;

-- Total de linhas e período dos dados
SELECT count(*)  AS total_linhas,
       min(time) AS primeira_leitura,
       max(time) AS ultima_leitura
FROM sensor_data;

-- 4. Lista os chunks e o intervalo de cada um
SELECT chunk_name, range_start, range_end
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sensor_data'
ORDER BY range_start;

-- Quantidade de linhas por chunk
SELECT tableoid::regclass AS chunk,
       count(*)           AS linhas
FROM sensor_data
GROUP BY tableoid
ORDER BY chunk;

-- Tamanho da hypertable
SELECT pg_size_pretty(hypertable_size('sensor_data')) AS tamanho_hypertable;



-- ============================================================
-- DEMONSTRAÇÃO 2: DESEMPENHO COM EXPLAIN ANALYZE
-- ============================================================

-- 1. Copia os dados para uma tabela comum (sem chunks)
CREATE TABLE sensor_data_plain AS
SELECT * FROM sensor_data
ORDER BY time;

-- Atualiza as estatísticas do planejador
ANALYZE sensor_data_plain;

-- Compara a contagem de linhas das duas tabelas
SELECT (SELECT count(*) FROM sensor_data)       AS hypertable,
       (SELECT count(*) FROM sensor_data_plain) AS tabela_comum;

-- 2. Tabela comum SEM índice -------------------------------------------------

-- Consulta 1: média da última hora
EXPLAIN ANALYZE
SELECT avg(temperatura)
FROM sensor_data_plain
WHERE time >= now() - interval '1 hour';

-- Consulta 2: média horária dos últimos 7 dias
EXPLAIN ANALYZE
SELECT time_bucket('1 hour', time) AS hora,
       avg(temperatura)
FROM sensor_data_plain
WHERE time >= now() - interval '7 days'
GROUP BY hora
ORDER BY hora;

-- Consulta 3: média diária entre 30 e 14 dias atrás
EXPLAIN ANALYZE
SELECT time_bucket('1 day', time) AS dia,
       avg(temperatura) AS temp_media
FROM sensor_data_plain
WHERE time >= now() - interval '30 days'
  AND time <  now() - interval '14 days'
GROUP BY dia
ORDER BY dia;

-- 3. Tabela comum COM índice -------------------------------------------------

CREATE INDEX idx_plain_time ON sensor_data_plain (time DESC);
ANALYZE sensor_data_plain;

-- Consulta 1 com índice
EXPLAIN ANALYZE
SELECT avg(temperatura)
FROM sensor_data_plain
WHERE time >= now() - interval '1 hour';

-- Consulta 2 com índice
EXPLAIN ANALYZE
SELECT time_bucket('1 hour', time) AS hora,
       avg(temperatura)
FROM sensor_data_plain
WHERE time >= now() - interval '7 days'
GROUP BY hora
ORDER BY hora;

-- Consulta 3 com índice
EXPLAIN ANALYZE
SELECT time_bucket('1 day', time) AS dia,
       avg(temperatura) AS temp_media
FROM sensor_data_plain
WHERE time >= now() - interval '30 days'
  AND time <  now() - interval '14 days'
GROUP BY dia
ORDER BY dia;

-- 4. Hypertable ---------------------------------------

-- Consulta 1 na hypertable
EXPLAIN ANALYZE
SELECT avg(temperatura)
FROM sensor_data
WHERE time >= now() - interval '1 hour';

-- Consulta 2 na hypertable
EXPLAIN ANALYZE
SELECT time_bucket('1 hour', time) AS hora,
       avg(temperatura)
FROM sensor_data
WHERE time >= now() - interval '7 days'
GROUP BY hora
ORDER BY hora;

-- Consulta 3 na hypertable
EXPLAIN ANALYZE
SELECT time_bucket('1 day', time) AS dia,
       avg(temperatura) AS temp_media
FROM sensor_data
WHERE time >= now() - interval '30 days'
  AND time <  now() - interval '14 days'
GROUP BY dia
ORDER BY dia;

-- 5. Tamanho (dados, índices e total)

-- Hypertable
SELECT pg_size_pretty(table_bytes) AS dados,
       pg_size_pretty(index_bytes) AS indices,
       pg_size_pretty(total_bytes) AS total
FROM hypertable_detailed_size('sensor_data');

-- Tabela comum
SELECT pg_size_pretty(pg_table_size('sensor_data_plain'))          AS dados,
       pg_size_pretty(pg_indexes_size('sensor_data_plain'))        AS indices,
       pg_size_pretty(pg_total_relation_size('sensor_data_plain')) AS total;



-- ============================================================
-- DEMONSTRAÇÃO 3: CONTINUOUS AGGREGATE E COMPRESSÃO
-- ============================================================

-- 1. Cria o resumo por hora (média de temperatura, umidade e nº de leituras)
CREATE MATERIALIZED VIEW sensor_hourly
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', time) AS hora,
       avg(temperatura)            AS temp_media,
       avg(umidade)                AS umid_media,
       count(*)                    AS leituras
FROM sensor_data
GROUP BY hora
WITH NO DATA;

-- Política: atualiza o resumo a cada hora
SELECT add_continuous_aggregate_policy('sensor_hourly',
    start_offset      => INTERVAL '3 days',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- Calcula o resumo de todo o histórico
CALL refresh_continuous_aggregate('sensor_hourly', NULL, NULL);

-- Número de linhas do resumo
SELECT count(*) FROM sensor_hourly;

-- Tamanho da view materializada para o aggregate
SELECT pg_size_pretty(hypertable_size('sensor_hourly')) AS tamanho_aggregate;

-- 2. Aggregate nas 3 consultas (coluna "Aggregate" da tabela de resultados) ---

-- Consulta 1 via aggregate: média da última hora
-- (o aggregate já guarda a média por hora pronta; pegamos o bucket da hora atual)
EXPLAIN ANALYZE
SELECT temp_media
FROM sensor_hourly
WHERE hora = time_bucket('1 hour', now() - interval '1 hour');

-- Consulta 2 via aggregate: média horária dos últimos 7 dias
EXPLAIN ANALYZE
SELECT hora, temp_media
FROM sensor_hourly
WHERE hora >= now() - interval '7 days'
ORDER BY hora;

-- Consulta 3 via aggregate: média diária entre 30 e 14 dias atrás
-- (reagrega os buckets horários por dia usando média ponderada pelo número
--  de leituras de cada hora, o que dá o resultado exato mesmo com horas
--  incompletas nas pontas da série; time_bucket usa UTC, o mesmo critério
--  da consulta na tabela bruta)
EXPLAIN ANALYZE
SELECT time_bucket('1 day', hora) AS dia,
       sum(temp_media * leituras) / sum(leituras) AS temp_media
FROM sensor_hourly
WHERE hora >= now() - interval '30 days'
  AND hora <  now() - interval '14 days'
GROUP BY dia
ORDER BY dia;



-- 3. Compressão ---------------------------------------------------------------

-- Tamanho antes
SELECT pg_size_pretty(hypertable_size('sensor_data')) AS tamanho_antes;

-- Habilita o columnstore (agrupado por sensor, ordenado por tempo)
ALTER TABLE sensor_data SET (
    timescaledb.enable_columnstore = true,
    timescaledb.segmentby = 'sensor_id',
    timescaledb.orderby   = 'time DESC'
);

-- Política: comprime automaticamente os chunks com mais de 7 dias
CALL add_columnstore_policy('sensor_data', after => INTERVAL '7 days');

-- Comprime agora os chunks antigos (a política roda em segundo plano)
SELECT compress_chunk(c, if_not_compressed => true)
FROM show_chunks('sensor_data', older_than => INTERVAL '7 days') c;

-- Chunks da hypertable, com a indicação de quais estão comprimidos
SELECT * FROM timescaledb_information.chunks
WHERE hypertable_name = 'sensor_data'
ORDER BY range_start;

-- Tamanho depois (somente chunks antigos comprimidos)
SELECT pg_size_pretty(hypertable_size('sensor_data')) AS tamanho_depois;

-- Consulta 1 depois (dados recentes, continuam não comprimidos: resultado
-- deve ficar igual ao "antes", pois esses chunks nao entram na politica)
EXPLAIN ANALYZE
SELECT avg(temperatura)
FROM sensor_data
WHERE time >= now() - interval '1 hour';

-- Consulta 2 depois (mesma observação: dados recentes, não comprimidos)
EXPLAIN ANALYZE
SELECT time_bucket('1 hour', time) AS hora,
       avg(temperatura)
FROM sensor_data
WHERE time >= now() - interval '7 days'
GROUP BY hora
ORDER BY hora;

-- Consulta 3 depois (mesmo período 30-14 dias atrás, agora comprimido:
-- aqui sim deve aparecer uma diferença real de desempenho)
EXPLAIN ANALYZE
SELECT time_bucket('1 day', time) AS dia,
       avg(temperatura) AS temp_media
FROM sensor_data
WHERE time >= now() - interval '30 days'
  AND time <  now() - interval '14 days'
GROUP BY dia
ORDER BY dia;
