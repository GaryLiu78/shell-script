#!/bin/bash
# scripts/run_pipeline.sh - Oracle流水线入口

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "请通过 run.sh 调用: ./run.sh pipeline" >&2
    exit 1
fi

init_environment "pipeline"
source "$SCRIPTS_DIR/common.sh"

# 注册模块
register_module "database" "$MODULES_DIR/database"
register_module "backup" "$MODULES_DIR/backup"
register_module "report" "$MODULES_DIR/report"
load_modules || exit 1

# 注册清理
for m in database backup report; do register_module_cleanup "$m"; done

main() {
    log_info "========== Oracle数据流水线启动 =========="
    check_dependencies "sqlplus" "expdp" "impdp" "python3"
    
    local start_time=$(date +%s)
    local work_dir=$(create_module_temp_dir)
    
    # Stage 1: Oracle数据库准备
    log_info ">>> Stage 1: 检查Oracle数据库 <<<"
    database_main
    
    # Stage 2: 验证数据库连接
    log_info ">>> Stage 2: 验证Oracle连接 <<<"
    if ! oracle_check_connection; then
        die "Oracle数据库连接失败"
    fi
    
    # Stage 3: 获取数据库统计信息
    log_info ">>> Stage 3: 收集统计信息 <<<"
    oracle_get_stats "$work_dir"
    
    # Stage 4: 备份数据库
    log_info ">>> Stage 4: 备份数据库 <<<"
    local backup_file=$(oracle_full_backup "$work_dir")
    
    # Stage 5: 生成报表
    log_info ">>> Stage 5: 生成报表 <<<"
    report_generate "oracle_pipeline_report"
    
    # Stage 6: 清理旧数据
    log_info ">>> Stage 6: 清理归档日志 <<<"
    oracle_cleanup_archivelog
    
    local duration=$(($(date +%s) - start_time))
    log_success "Oracle流水线完成 (耗时: ${duration}秒)"
    
    # 输出摘要
    echo ""
    echo "========== 流水线摘要 =========="
    echo "备份文件: $backup_file"
    echo "工作目录: $work_dir"
    echo "日志文件: $LOG_FILE"
    echo "================================"
    
    send_notification "Oracle流水线完成" "备份: $backup_file\n耗时: ${duration}秒"
}

main
