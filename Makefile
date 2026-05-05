.PHONY: health-check audit-verify backup-test dev stop logs

COMPOSE     = docker compose -f docker/docker-compose.yml
COMPOSE_DEV = $(COMPOSE) -f docker/docker-compose.dev.yml
DB_NAME     ?= openemr

health-check:
	@echo "=== Container Status ==="
	@$(COMPOSE) ps
	@echo ""
	@echo "=== OpenEMR Health ==="
	@$(COMPOSE) exec openemr curl -sf http://localhost/openemr/health/ && echo "OpenEMR: OK" || echo "OpenEMR: FAIL"
	@echo ""
	@echo "=== Integration Service Health ==="
	@$(COMPOSE) exec integration curl -sf http://localhost:8000/health && echo "Integration: OK" || echo "Integration: FAIL"
	@echo ""
	@echo "=== Database Health ==="
	@$(COMPOSE) exec db healthcheck.sh --connect --innodb_initialized && echo "DB: OK" || echo "DB: FAIL"

audit-verify:
	@echo "=== Audit Log — Last 10 Entries ==="
	@$(COMPOSE) exec db mysql -u root -p"$$MYSQL_ROOT_PASSWORD" $(DB_NAME) \
		-e "SELECT user, event, patient_id, DATE_FORMAT(date, '%Y-%m-%d %H:%i:%s') AS date FROM audit_master ORDER BY date DESC LIMIT 10;" \
		2>/dev/null || echo "No audit entries yet or audit_master not found."
	@echo ""
	@echo "=== Audit Globals Configuration ==="
	@$(COMPOSE) exec db mysql -u root -p"$$MYSQL_ROOT_PASSWORD" $(DB_NAME) \
		-e "SELECT gl_name, gl_value FROM globals WHERE gl_name LIKE '%audit%' OR gl_name LIKE '%log%';" \
		2>/dev/null

backup-test:
	@echo "=== Running Backup Test ==="
	@bash docker/backup/backup.sh --test
	@echo "Backup test complete."

dev:
	$(COMPOSE_DEV) up -d
	@echo ""
	@echo "Dev environment started:"
	@echo "  OpenEMR:     http://localhost:8080"
	@echo "  Integration: http://localhost:8000/docs"
	@echo "  Traefik UI:  http://localhost:8090"
	@echo "  DB port:     localhost:3306"

stop:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100
