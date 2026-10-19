# TimescaleDB vs. PostgreSQL Benchmark: Análise de Séries Temporais em IoT

Repositório com o código SQL e material do seminário desenvolvido para a disciplina de **Banco de Dados II (BAN2002)** do curso de Ciência da Computação na **UDESC Joinville**.

O objetivo deste projeto é comparar na prática a eficiência do PostgreSQL relacional puro e da extensão **TimescaleDB** na gestão de séries temporais de alto volume, avaliando consumo em disco e tempo de execução de consultas analíticas.

---

## 📊 Cenário dos Dados

* **Aplicação:** Monitoramento contínuo de temperatura e umidade em sensores IoT.
* **Frequência:** 1 leitura por minuto por sensor durante 30 dias.
* **Escala:** 10 sensores gerando um total de 432.010 registros.
* **Particionamento:** Chunks de 7 dias na Hypertable do TimescaleDB.

---

## 🔬 Estrutura dos Testes

1. **Demonstração 1: Hypertable e Inserção de Dados**
   * Habilitação da extensão `timescaledb`.
   * Criação e conversão da tabela em Hypertable particionada por tempo.
   * População em massa simulada via `generate_series`.
2. **Demonstração 2: Comparação de Desempenho com EXPLAIN ANALYZE**
   * Comparativo entre Tabela Comum (sem índice), Tabela Comum (com índice B-Tree) e Hypertable.
   * Execução de três janelas de consulta: última hora, últimos 7 dias e período antigo de 30 a 14 dias atrás.
3. **Demonstração 3: Continuous Aggregates e Compressão Colunar**
   * Criação de view materializada contínua por hora (`sensor_hourly`).
   * Aplicação do armazenamento em colunas (*columnstore*) agrupado por sensor e ordenado por tempo para dados com mais de 7 dias.

---

## 📈 Resultados Obtidos

Os testes foram executados medindo a mediana do tempo real de execução (`Execution Time`) via `EXPLAIN ANALYZE`:

| Métrica / Consulta | Tabela Comum (Sem Índice) | Tabela Comum (Com Índice) | Hypertable | Continuous Aggregate | Hypertable Comprimida |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Tamanho em Disco** | 25 MB | 29 MB | 30 MB | 128 KB (view) | 16 MB |
| **Consulta 1** *(Média última hora)* | 17,00 ms | 0,17 ms | 0,26 ms | 0,10 ms | 0,25 ms |
| **Consulta 2** *(Média 7 dias)* | 68,00 ms | 27,00 ms | 34,00 ms | 0,10 ms | 34,00 ms |
| **Consulta 3** *(Média 30 a 14 dias)* | 138,00 ms | 59,00 ms | 79,00 ms | 0,30 ms | 16,00 ms |

---

## 🚀 Como Executar

### 1. Subir o ambiente com Docker

```bash
docker run -d --name timescaledb \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=suasenha \
  timescale/timescaledb:latest-pg18
```

### 2. Executar o Script SQL

Conecte-se ao banco via pgAdmin ou client `psql` e execute o arquivo script contido neste repositório:

```bash
psql -h localhost -U postgres -d postgres -f Timescale_DB_Kelwin_Uriel.sql
```

---

## 👥 Autores

* **Kelwin Efrain Bagnhuk da Silva**
* **Uriel Pacheco de Souza**
* **Professor:** Prof. Dr. Fabiano Baldo
* **Instituição:** Universidade do Estado de Santa Catarina (UDESC) - CCT
