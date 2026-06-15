#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[AVISO]${NC} $*"; }
log_error() { echo -e "${RED}[ERRO]${NC} $*"; }

CONTAINER_ENGINE=""
COMPOSE_CMD=()
COMPOSE_FILES=(-f docker-compose.yml)

detect_container_engine() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        CONTAINER_ENGINE="docker"
        if docker compose version >/dev/null 2>&1; then
            COMPOSE_CMD=(docker compose)
        elif command -v docker-compose >/dev/null 2>&1; then
            COMPOSE_CMD=(docker-compose)
        else
            log_error "Docker encontrado, mas docker compose não está disponível."
            exit 1
        fi
        return 0
    fi

    if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
        CONTAINER_ENGINE="podman"
        COMPOSE_FILES+=(-f docker-compose.podman.yml)
        if podman compose version >/dev/null 2>&1; then
            COMPOSE_CMD=(podman compose)
        elif command -v podman-compose >/dev/null 2>&1; then
            COMPOSE_CMD=(podman-compose)
        else
            log_error "Podman encontrado, mas podman compose não está disponível."
            log_info "Instale com: sudo dnf install podman-compose (RHEL/Fedora)"
            exit 1
        fi
        return 0
    fi

    log_error "Nenhum runtime de contêiner ativo foi encontrado (Docker ou Podman)."
    log_info "Inicie o Docker Desktop ou o serviço Podman e execute novamente."
    exit 1
}

prepare_data_directories() {
    log_info "Preparando diretórios de persistência..."
    mkdir -p data/postgres data/prometheus data/grafana

    if [[ "$CONTAINER_ENGINE" == "podman" ]] && command -v getenforce >/dev/null 2>&1; then
        local selinux_status
        selinux_status="$(getenforce 2>/dev/null || echo Disabled)"
        if [[ "$selinux_status" != "Disabled" ]]; then
            log_info "SELinux ativo ($selinux_status). Aplicando contexto nos volumes (:Z no compose)."
            if command -v chcon >/dev/null 2>&1; then
                chcon -R -t container_file_t data/postgres data/prometheus data/grafana 2>/dev/null || \
                    log_warn "Não foi possível aplicar chcon; o sufixo :Z nos volumes deve resolver."
            fi
        fi
    fi
}

is_stack_running() {
    local running_services
    running_services="$("${COMPOSE_CMD[@]}" "${COMPOSE_FILES[@]}" ps --services --filter status=running 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$running_services" -gt 0 ]]
}

show_endpoints() {
    echo
    log_ok "Ambiente disponível:"
    echo "  API (via Nginx):     http://localhost:8080/events"
    echo "  Documentação:        http://localhost:8080/docs"
    echo "  Grafana:             http://localhost:8080/grafana/  (admin / admin)"
    echo "  Prometheus:          http://localhost:8080/prometheus/"
    echo
}

main() {
    log_info "Validando runtime de contêiner..."
    detect_container_engine
    log_ok "Usando ${CONTAINER_ENGINE} (${COMPOSE_CMD[*]})"

    prepare_data_directories

    if is_stack_running; then
        log_warn "Pelo menos parte da infraestrutura já está em execução."
        log_info "Executando '${COMPOSE_CMD[*]} up -d' para garantir convergência do estado..."
    else
        log_info "Subindo infraestrutura monitorada..."
    fi

    "${COMPOSE_CMD[@]}" "${COMPOSE_FILES[@]}" up -d --build

    log_info "Aguardando estabilização dos serviços..."
    sleep 5

    echo
    log_info "Status dos contêineres:"
    "${COMPOSE_CMD[@]}" "${COMPOSE_FILES[@]}" ps

    echo
    log_info "Verificando saúde dos serviços principais..."
    if curl -fsS http://localhost:8080/nginx-health >/dev/null 2>&1; then
        log_ok "Nginx respondendo na porta 8080"
    else
        log_warn "Nginx ainda não respondeu; aguarde alguns segundos e tente novamente."
    fi

    if curl -fsS http://localhost:8080/health >/dev/null 2>&1; then
        log_ok "API acessível via load balancer"
    else
        log_warn "API ainda não respondeu via Nginx."
    fi

    show_endpoints
}

main "$@"
