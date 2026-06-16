# Sports Score API — Infraestrutura Monitorada

Ambiente containerizado com **Nginx** (proxy + load balancer), **duas instâncias FastAPI**, **PostgreSQL persistente** e stack de observabilidade (**Prometheus + Grafana**).

A API registra placares esportivos. O foco do projeto é a infraestrutura, não a lógica de negócio.

Link do Vídeo no YouTube - https://www.youtube.com/watch?v=zMLV49uJ7tg

---

## Arquitetura

```
Internet ──:8080──► Nginx ──┬──► app1:8000 ──┐
                            ├──► app2:8000 ──┼──► PostgreSQL:5432
                            ├──► Grafana:3000
                            └──► Prometheus:9090
                                    ▲
                              app1 / app2
```

Apenas o **Nginx** expõe porta no host. Demais serviços usam a rede interna `sports-internal`.


| Serviço     | Função                                  |
| ----------- | --------------------------------------- |
| nginx       | Reverse proxy e load balancer           |
| app1 / app2 | Instâncias idênticas da API FastAPI     |
| db          | PostgreSQL com volume persistente       |
| prometheus  | Coleta métricas das instâncias da API   |
| grafana     | Visualização via dashboard provisionado |


---

## Pré-requisitos

- Docker Desktop (macOS/Windows) **ou** Podman (Linux/RHEL/Fedora)
- `docker compose` ou `podman compose`
- Porta **8080** livre

> **macOS:** abra o Docker Desktop — não use `systemctl` (comando inexistente no Mac). Não é necessário `sudo`.

---

## Subir o ambiente

```bash
cd Linux_project
chmod +x start-infra.sh   # primeira vez
./start-infra.sh
```

O script detecta Docker/Podman, valida o daemon, cria `data/`, aplica overlay SELinux no Podman e executa `compose up -d --build`. Se o ambiente já estiver rodando, reconverge o estado.

Aguarde 1–3 min na primeira execução. Confirme com:

```bash
docker compose ps   # todos healthy ou running
```

---

## Acesso


| Serviço    | URL                                                                    | Credenciais   |
| ---------- | ---------------------------------------------------------------------- | ------------- |
| API        | [http://localhost:8080/events](http://localhost:8080/events)           | —             |
| Swagger    | [http://localhost:8080/docs](http://localhost:8080/docs)               | —             |
| Grafana    | [http://localhost:8080/grafana/](http://localhost:8080/grafana/)       | admin / admin |
| Prometheus | [http://localhost:8080/prometheus/](http://localhost:8080/prometheus/) | —             |


> Use **Chrome ou Safari** para Grafana e Prometheus. O Simple Browser do Cursor não renderiza essas interfaces corretamente.

---

## API


| Método | Path           | Descrição                     |
| ------ | -------------- | ----------------------------- |
| GET    | `/health`      | Status da instância           |
| GET    | `/events`      | Lista eventos                 |
| POST   | `/events`      | Cria evento                   |
| GET    | `/events/{id}` | Busca evento por ID           |
| GET    | `/metrics`     | Métricas Prometheus (interno) |


**Exemplo — criar evento:**

```bash
curl -X POST http://localhost:8080/events \
  -H "Content-Type: application/json" \
  -d '{"sport":"Futebol","home_team":"Brasil","away_team":"Argentina","home_score":2,"away_score":1}'
```

**Exemplo — listar eventos:**

```bash
curl http://localhost:8080/events
```

O campo `"instance"` (`app1` ou `app2`) confirma o balanceamento do Nginx:

```bash
for i in $(seq 1 6); do curl -s http://localhost:8080/health; echo; done
```

> `/events` retorna JSON puro. Para interface visual, use `/docs`.

---

## Monitoramento

**Prometheus** — acesse [http://localhost:8080/prometheus/targets](http://localhost:8080/prometheus/targets) e confirme:


| Job        | Alvos                | Esperado |
| ---------- | -------------------- | -------- |
| sports-api | app1:8000, app2:8000 | UP       |
| prometheus | localhost:9090       | UP       |


**Grafana** — login em [http://localhost:8080/grafana/](http://localhost:8080/grafana/), dashboard em **Sports Infra → Sports API - Monitoramento**. Gere tráfego para ver gráficos:

```bash
for i in $(seq 1 20); do curl -s http://localhost:8080/events > /dev/null; done
```

**Métricas expostas pela API** (`prometheus-fastapi-instrumentator`):

- `http_requests_total` — requisições por rota, método e status
- `http_request_duration_seconds` — latência por rota

---

## Encerrar o ambiente

```bash
docker compose down                              # para contêineres, preserva dados
docker compose down -v                           # remove volumes do Compose
rm -rf data/postgres data/grafana data/prometheus  # apaga dados do host
```

Para subir novamente: `./start-infra.sh`

---

## Comandos úteis


| Ação              | Comando                        |
| ----------------- | ------------------------------ |
| Subir             | `./start-infra.sh`             |
| Status            | `docker compose ps`            |
| Logs              | `docker compose logs -f app1`  |
| Reiniciar serviço | `docker compose restart nginx` |


---

## Estrutura do projeto

```
├── app/                         # FastAPI + Dockerfile
├── nginx/nginx.conf             # Load balancer
├── prometheus/prometheus.yml    # Scrape configs
├── grafana/provisioning/        # Datasource + dashboard
├── docker-compose.yml           # Compose principal
├── docker-compose.podman.yml    # Overlay SELinux (Podman)
├── start-infra.sh               # Script de inicialização
└── data/                        # Volumes persistentes (gerado ao subir)
```

---

## Persistência e segurança

- Dados do PostgreSQL em `./data/postgres/` — persistem após `docker compose down`
- Banco sem porta exposta no host
- Podman + SELinux: `docker-compose.podman.yml` aplica sufixo `:Z` nos volumes

---

## Solução de problemas


| Problema                         | Solução                                                                                                                                                                                   |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Runtime não encontrado           | Abra o Docker Desktop ou inicie o Podman                                                                                                                                                  |
| `systemctl: command not found`   | macOS — use Docker Desktop                                                                                                                                                                |
| Porta 8080 em uso                | Altere `"8080:80"` em `docker-compose.yml`                                                                                                                                                |
| Tela em branco em `/events`      | Normal — é JSON; use `/docs` ou `curl`                                                                                                                                                    |
| Prometheus em branco             | Use [http://localhost:8080/prometheus/](http://localhost:8080/prometheus/) no Chrome/Safari                                                                                               |
| Grafana "No data" nos painéis    | Reinicie o Grafana (`docker compose restart grafana`); confira em **Connections → Data sources → Prometheus** se a URL é `http://prometheus:9090/prometheus`; gere tráfego e aguarde ~30s |
| Build falha com `Read timed out` | Conexão lenta — rode `./start-infra.sh` novamente                                                                                                                                         |
| Permissão no Podman/SELinux      | Use `./start-infra.sh` (aplica overlay automaticamente)                                                                                                                                   |


