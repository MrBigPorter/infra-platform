.PHONY: up down restart ps logs logs-loki logs-promtail logs-grafana help

COMPOSE_FILE := compose.monitoring.yml

up: ## Start the monitoring stack (Loki + Promtail + Grafana)
	docker compose -f $(COMPOSE_FILE) up -d

down: ## Stop and remove all monitoring containers
	docker compose -f $(COMPOSE_FILE) down

restart: ## Restart the monitoring stack
	docker compose -f $(COMPOSE_FILE) down
	docker compose -f $(COMPOSE_FILE) up -d

ps: ## Show container status
	docker compose -f $(COMPOSE_FILE) ps

logs: ## Tail logs from all monitoring services
	docker compose -f $(COMPOSE_FILE) logs --tail=50 -f

logs-loki: ## Tail Loki logs
	docker compose -f $(COMPOSE_FILE) logs --tail=30 -f loki

logs-promtail: ## Tail Promtail logs
	docker compose -f $(COMPOSE_FILE) logs --tail=30 -f promtail

logs-grafana: ## Tail Grafana logs
	docker compose -f $(COMPOSE_FILE) logs --tail=30 -f grafana

help: ## Show this help message
	@echo 'Usage: make <target>'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
