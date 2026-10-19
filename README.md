# TimescaleDB vs. PostgreSQL Benchmark: Análise de Séries Temporais em IoT

Repositório com o código SQL e material do seminário desenvolvido para a disciplina de **Banco de Dados II (BAN2002)** do curso de Ciência da Computação na **UDESC Joinville**[cite: 24, 46].

O objetivo deste projeto é comparar na prática a eficiência do PostgreSQL relacional puro e da extensão **TimescaleDB** na gestão de séries temporais de alto volume, avaliando consumo em disco e tempo de execução de consultas analíticas[cite: 24, 26, 42].

---

## 📊 Cenário dos Dados

* **Aplicação:** Monitoramento contínuo de temperatura e umidade em sensores IoT[cite: 24, 27, 42].
* **Frequência:** 1 leitura por minuto por sensor durante 30 dias[cite: 24, 42, 46].
* **Escala:** 10 sensores gerando um total de 432.010 registros[cite: 36, 42, 46].
* **Particionamento:** Chunks de 7 dias na Hypertable do TimescaleDB[cite: 31, 36, 46].

---

## 🔬 Estrutura dos Testes

1. **Demonstração 1: Hypertable e Inserção de Dados**
   * Habilitação da extensão `timescaledb`[cite: 28, 46].
   * Criação e conversão da tabela em Hypertable particionada por tempo[cite: 31, 36, 46].
   * População em massa simulada via `generate_series`[cite: 36, 46].
2. **Demonstração 2: Comparação de Desempenho com EXPLAIN ANALYZE**
   * Comparativo entre Tabela Comum (sem índice), Tabela Comum (com índice B-Tree) e Hypertable[cite: 38, 42, 46].
   * Execução de três janelas de consulta: última hora, últimos 7 dias e período antigo de 30 a 14 dias atrás[cite: 24, 42, 46].
3. **Demonstração 3: Continuous Aggregates e Compressão Colunar**
   * Criação de view materializada contínua por hora (`sensor_hourly`)[cite: 34, 40, 46].
   * Aplicação do armazenamento em colunas (*columnstore*) agrupado por sensor e ordenado por tempo para dados com mais de 7 dias[cite: 35, 40, 46].

---

## 📈 Resultados Obtidos

Os testes foram executados medindo a mediana do tempo real de execução (`Execution Time`) via `EXPLAIN ANALYZE`[cite: 33, 42]:

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
