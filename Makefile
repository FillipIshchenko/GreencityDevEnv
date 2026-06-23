# Convenience wrapper around the dev environment.
# Run `make help` for the list.

COMPOSE      := docker compose
APP_COMPOSE  := docker compose -f app/docker-compose.app.yml --project-directory app

.DEFAULT_GOAL := help

.PHONY: help setup up down restart logs jenkins-logs sonar-logs \
        app-up app-down app-build app-logs app-ps check-upstream clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## Full first-time setup (clones repos, starts tooling, bootstraps Sonar)
	./setup.sh

up: ## Start the CI tooling stack (Jenkins + SonarQube)
	$(COMPOSE) up -d --build

down: ## Stop the CI tooling stack (keeps volumes/data)
	$(COMPOSE) down

restart: ## Restart the CI tooling stack
	$(COMPOSE) restart

logs: ## Tail all CI tooling logs
	$(COMPOSE) logs -f

jenkins-logs: ## Tail Jenkins logs
	$(COMPOSE) logs -f jenkins

sonar-logs: ## Tail SonarQube logs
	$(COMPOSE) logs -f sonarqube

app-up: ## Build + start the GreenCity app stack manually
	$(APP_COMPOSE) up -d --build

app-down: ## Stop the GreenCity app stack
	$(APP_COMPOSE) down

app-build: ## Rebuild all app images
	$(APP_COMPOSE) build

app-logs: ## Tail app logs
	$(APP_COMPOSE) logs -f

app-ps: ## Show app container status
	$(APP_COMPOSE) ps

check-upstream: ## Manually run the upstream check (no pull)
	REPOS_DIR=$(PWD)/repos bash scripts/check-upstream.sh

clean: ## Stop everything and DELETE all volumes (Jenkins/Sonar/app data)
	$(COMPOSE) down -v
	$(APP_COMPOSE) down -v || true
