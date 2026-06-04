# Makefile

.PHONY: help nostream clean status install test init

PROJECT_ROOT := $(shell pwd)
export PROJECT_ROOT

GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

help:
	@echo "$(GREEN)Command List:$(NC)"
	@echo "  $(YELLOW)make nostream$(NC)   - Check channel no streaming status"
	@echo "  $(YELLOW)make clean$(NC)      - Clean up temporary files"
	@echo "  $(YELLOW)make status$(NC)     - Show Status"
	@echo "  $(YELLOW)make install$(NC)    - Installed to OS"
	@echo "  $(YELLOW)make test$(NC)       - Run testing"

nostream:
	@bash ./run.sh nostream

clean:
	@bash ./run.sh clean

status:
	@bash ./run.sh status

install:
	@chmod +x run.sh lib/*.sh modules/*/*.sh tests/*.sh
	@sudo ln -sf $(PROJECT_ROOT)/run.sh /usr/local/bin/myapp
	@echo "$(GREEN)Installed, use 'myapp' command $(NC)"

test:
	@echo "Run testing ..."
	@bash -n run.sh
	@find lib modules pipelines tests config -type f \( -name '*.sh' -o -name '*.conf' \) -print0 | xargs -0 -n1 bash -n
	@bash tests/test_alarm_format.sh
	@echo "$(GREEN)Synthx verified $(NC)"

init:
	@mkdir -p logs temp backups reports
	@echo "Project initialized"
