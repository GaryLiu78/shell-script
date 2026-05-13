#!/bin/bash
# scripts/run_backup.sh - 运行备份模块

# 获取项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载库
source "$PROJECT_ROOT/bin/bash_lib.sh"

# 设置模块名
MODULE_NAME="backup"

# 初始化环境
init_environment "backup"

# 业务逻辑
log_info "========== 备份任务开始 =========="

# 注册模块清理
register_module_cleanup "backup"

# 加载模块
register_module "backup" "$PROJECT_ROOT/modules/backup"
load_modules

# 创建临时目录
WORK_DIR=$(create_module_temp_dir)
log_info "工作目录: $WORK_DIR"

# 执行备份
backup_main
backup_create "etc_backup" "/etc"

log_success "备份任务完成"
