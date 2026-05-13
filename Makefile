# Makefile - 项目构建和管理
.PHONY: help backup pipeline report clean status install test

PROJECT_ROOT := $(shell pwd)
export PROJECT_ROOT

# 颜色定义
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help:
	@echo "$(GREEN)可用命令:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make backup$(NC)     - 运行备份"
	@echo "  $(YELLOW)make pipeline$(NC)   - 运行数据流水线"
	@echo "  $(YELLOW)make report$(NC)     - 生成报表"
	@echo "  $(YELLOW)make clean$(NC)      - 清理临时文件"
	@echo "  $(YELLOW)make status$(NC)     - 查看项目状态"
	@echo "  $(YELLOW)make install$(NC)    - 安装到系统"
	@echo "  $(YELLOW)make test$(NC)       - 运行测试"

backup:
	@./run.sh backup

pipeline:
	@./run.sh pipeline

report:
	@./run.sh report

clean:
	@./run.sh clean

status:
	@./run.sh status

install:
	@echo "安装项目启动器..."
	@chmod +x run.sh
	@sudo ln -sf $(PROJECT_ROOT)/run.sh /usr/local/bin/myapp
	@echo "已安装，可以使用 'myapp' 命令"

test:
	@echo "运行测试..."
	@bash -n run.sh
	@for script in scripts/*.sh; do \
		echo "检查 $$script..."; \
		bash -n "$$script"; \
	done
	@echo "所有脚本语法检查通过"
