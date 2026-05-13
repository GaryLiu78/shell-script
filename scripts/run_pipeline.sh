#!/bin/bash
# scripts/run_pipeline.sh - 完整数据流水线

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/bin/bash_lib.sh"

# 设置流水线模式
MODULE_NAME="pipeline"

# 初始化环境
init_environment "pipeline"

log_info "========== 数据流水线启动 =========="

# 注册所有模块
register_module "database" "$PROJECT_ROOT/modules/database"
register_module "backup" "$PROJECT_ROOT/modules/backup"
register_module "report" "$PROJECT_ROOT/modules/report"

# 注册模块清理（按逆序清理）
register_module_cleanup "report"
register_module_cleanup "backup"
register_module_cleanup "database"

# 加载所有模块
load_modules

log_info "所有模块加载完成"

# ========== 执行流水线 ==========

# 步骤1: 准备数据库
log_info "步骤1: 准备数据库"
database_main

# 步骤2: 备份数据库
log_info "步骤2: 备份数据库"
BACKUP_FILE=$(db_backup "pre_pipeline")
log_info "备份文件: $BACKUP_FILE"

# 步骤3: 处理数据
log_info "步骤3: 生成报表"
REPORT_FILE=$(report_generate "daily_report")
log_info "报表文件: $REPORT_FILE"

# 步骤4: 归档备份
log_info "步骤4: 归档备份"
backup_create "pipeline_archive" "$BACKUP_FILE"

# ========== 完成 ==========
log_success "数据流水线执行完成"
log_info "备份文件: $BACKUP_FILE"
log_info "报表文件: $REPORT_FILE"

# 显示执行摘要
echo ""
echo "========== 执行摘要 =========="
echo "数据库备份: $BACKUP_FILE"
echo "报表生成: $REPORT_FILE"
echo "日志文件: $LOG_FILE"
echo "=============================="
