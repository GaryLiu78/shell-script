# Makefile - 项目管理（Oracle版本）

.PHONY: help backup pipeline report clean status install test init check-oracle

PROJECT_ROOT := $(shell pwd)
export PROJECT_ROOT

GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
RED := \033[0;31m
NC := \033[0m

help:
	@echo "$(GREEN)Oracle备份系统可用命令:$(NC)"
	@echo "  $(YELLOW)make backup$(NC)        - 运行Oracle全库备份"
	@echo "  $(YELLOW)make backup-schema$(NC) - 备份指定Schema (SCHEMA=HR)"
	@echo "  $(YELLOW)make pipeline$(NC)      - 运行完整流水线"
	@echo "  $(YELLOW)make report$(NC)        - 生成报表"
	@echo "  $(YELLOW)make clean$(NC)         - 清理临时文件"
	@echo "  $(YELLOW)make status$(NC)        - 查看状态"
	@echo "  $(YELLOW)make check-oracle$(NC)  - 检查Oracle连接"
	@echo "  $(YELLOW)make install$(NC)       - 安装到系统"
	@echo "  $(YELLOW)make test$(NC)          - 运行测试"

backup:
	@./run.sh backup --full --compress

backup-schema:
	@if [ -z "$(SCHEMA)" ]; then \
		echo "$(RED)错误: 请指定SCHEMA参数$(NC)"; \
		echo "示例: make backup-schema SCHEMA=HR"; \
		exit 1; \
	fi
	@./run.sh backup --schema $(SCHEMA) --compress

pipeline:
	@./run.sh pipeline

report:
	@./run.sh report

clean:
	@./run.sh clean

status:
	@./run.sh status

check-oracle:
	@echo "$(YELLOW)检查Oracle连接...$(NC)"
	@sqlplus -S ${ORACLE_USER}/${ORACLE_PASS}@${ORACLE_HOST}:${ORACLE_PORT}/${ORACLE_SID} <<EOF
	SELECT '$(GREEN)Oracle连接成功$(NC)' as status FROM DUAL;
	EXIT;
EOF

install:
	@chmod +x run.sh bin/bash_lib.sh scripts/*.sh modules/*/main.sh
	@sudo ln -sf $(PROJECT_ROOT)/run.sh /usr/local/bin/orabackup
	@echo "$(GREEN)已安装，使用 'orabackup' 命令$(NC)"

test:
	@echo "运行语法检查..."
	@bash -n run.sh
	@bash -n bin/bash_lib.sh
	@for script in scripts/*.sh; do bash -n "$$script"; done
	@for module in modules/*/main.sh; do bash -n "$$module"; done
	@echo "$(GREEN)所有语法检查通过$(NC)"

init:
	@echo "初始化项目目录..."
	@mkdir -p logs temp backups reports
	@mkdir -p logs/database logs/backup logs/report
	@mkdir -p temp/database temp/backup temp/report
	@echo "配置文件示例:"
	@echo "  1. 编辑 config/global.conf 设置Oracle连接参数"
	@echo "  2. 设置 ORACLE_PASS 环境变量: export ORACLE_PASS='your_password'"
	@echo "  3. 运行 'make check-oracle' 验证连接"
	@echo "$(GREEN)初始化完成$(NC)"

env:
	@echo "$(GREEN)当前环境变量:$(NC)"
	@echo "ORACLE_HOST: $(ORACLE_HOST)"
	@echo "ORACLE_PORT: $(ORACLE_PORT)"
	@echo "ORACLE_SID: $(ORACLE_SID)"
	@echo "ORACLE_USER: $(ORACLE_USER)"
	@echo "ORACLE_SCHEMA: $(ORACLE_SCHEMA)"
	@echo "LOG_LEVEL: $(LOG_LEVEL)"
