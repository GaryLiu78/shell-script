#!/bin/bash
# run_pipeline.sh - 数据流水线入口 v2
# 
# 描述: 执行完整的数据处理流水线
# Stage: 数据库备份 → 数据处理 → 报表生成 → 归档

# 自动检测项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 验证并加载库
if [[ ! -f "$PROJECT_ROOT/bin/bash_lib.sh" ]]; then
    echo "错误: 找不到 bin/bash_lib.sh" >&2
    exit 1
fi

source "$PROJECT_ROOT/bin/bash_lib.sh"

# 配置
MODULE_NAME="pipeline"
STAGES=("database" "backup" "report")
SKIP_STAGES=()

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip)
            SKIP_STAGES+=("$2")
            shift 2
            ;;
        --debug)
            export DEBUG=true
            shift
            ;;
        --help)
            echo "流水线执行器"
            echo "用法: $0 [--skip stage] [--debug]"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# 初始化
init_environment "$MODULE_NAME"

log_info "========== 数据流水线启动 =========="
log_info "执行阶段: ${STAGES[*]}"
[[ ${#SKIP_STAGES[@]} -gt 0 ]] && log_info "跳过阶段: ${SKIP_STAGES[*]}"

# 注册模块
for stage in "${STAGES[@]}"; do
    if [[ -d "$PROJECT_ROOT/modules/$stage" ]]; then
        register_module "$stage" "$PROJECT_ROOT/modules/$stage"
        register_module_cleanup "$stage"
    else
        log_warn "模块不存在: $stage"
    fi
done

# 加载模块
load_modules

# 执行流水线
pipeline_start_time=$(date +%s)

# Stage 1: 数据库
if [[ ! " ${SKIP_STAGES[*]} " =~ " database " ]]; then
    log_info ">>> Stage 1: 数据库模块 <<<"
    database_main
    db_backup "pipeline_stage1"
    log_success "Stage 1 完成"
else
    log_warn "跳过 Stage 1"
fi

# Stage 2: 备份
if [[ ! " ${SKIP_STAGES[*]} " =~ " backup " ]]; then
    log_info ">>> Stage 2: 备份模块 <<<"
    backup_main
    backup_create "pipeline_backup" "$PROJECT_ROOT/temp/database"
    log_success "Stage 2 完成"
else
    log_warn "跳过 Stage 2"
fi

# Stage 3: 报表
if [[ ! " ${SKIP_STAGES[*]} " =~ " report " ]]; then
    log_info ">>> Stage 3: 报表模块 <<<"
    report_generate "pipeline_report"
    log_success "Stage 3 完成"
else
    log_warn "跳过 Stage 3"
fi

# 计算耗时
pipeline_end_time=$(date +%s)
pipeline_duration=$((pipeline_end_time - pipeline_start_time))

log_success "数据流水线执行完成"
log_info "总耗时: ${pipeline_duration}秒"
