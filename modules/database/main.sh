#!/bin/bash
# modules/database/main.sh - Oracle数据库模块

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "错误: 此脚本应该被 source 调用" >&2
    exit 1
fi

log_info "Oracle数据库模块加载中..."

# Oracle连接配置
ORACLE_HOST="${ORACLE_HOST:-localhost}"
ORACLE_PORT="${ORACLE_PORT:-1521}"
ORACLE_SID="${ORACLE_SID:-ORCL}"
ORACLE_SERVICE="${ORACLE_SERVICE:-}"
ORACLE_USER="${ORACLE_USER:-system}"
ORACLE_PASS="${ORACLE_PASS:-}"
ORACLE_SCHEMA="${ORACLE_SCHEMA:-}"
ORACLE_HOME="${ORACLE_HOME:-/u01/app/oracle/product/19.3.0/dbhome_1}"

# 导出工具选择（优先使用expdp，降级到exp）
USE_EXPDP="${USE_EXPDP:-true}"

# 私有函数
_oracle_connect_string() {
    if [[ -n "$ORACLE_SERVICE" ]]; then
        echo "${ORACLE_USER}/${ORACLE_PASS}@//${ORACLE_HOST}:${ORACLE_PORT}/${ORACLE_SERVICE}"
    else
        echo "${ORACLE_USER}/${ORACLE_PASS}@${ORACLE_HOST}:${ORACLE_PORT}/${ORACLE_SID}"
    fi
}

_oracle_check_tools() {
    if [[ "$USE_EXPDP" == "true" ]] && command -v expdp &>/dev/null; then
        log_debug "使用expdp工具"
        return 0
    elif command -v exp &>/dev/null; then
        USE_EXPDP="false"
        log_debug "expdp不可用，使用exp工具"
        return 0
    else
        log_error "Oracle导出工具不可用"
        return 1
    fi
}

# 清理函数
cleanup_database() {
    log_info "清理Oracle数据库模块"
    safe_rm_dir "$TEMP_BASE_DIR/database"
    # 清理Oracle临时文件
    rm -f "$TEMP_BASE_DIR"/expdat.dmp 2>/dev/null || true
}

# 检查Oracle连接
oracle_check_connection() {
    log_info "检查Oracle连接: $ORACLE_HOST:$ORACLE_PORT/$ORACLE_SID"
    
    local connect_str="$(_oracle_connect_string)"
    if sqlplus -S "$connect_str" <<EOF >/dev/null 2>&1
SELECT 1 FROM DUAL;
EXIT;
EOF
    then
        log_success "Oracle连接成功"
        return 0
    else
        log_error "Oracle连接失败"
        return 1
    fi
}

# 执行SQL查询
oracle_query() {
    local sql="$1"
    local output_file="$2"
    local connect_str="$(_oracle_connect_string)"
    
    sqlplus -S "$connect_str" <<EOF > "$output_file" 2>&1
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
$sql
EXIT;
EOF
    
    return $?
}

# 获取数据库统计信息
oracle_get_stats() {
    local output_dir="$1"
    local stats_file="$output_dir/oracle_stats_$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "收集Oracle统计信息"
    
    cat > "$stats_file" << EOF
========================================
Oracle数据库统计信息
采集时间: $(date)
========================================

-- 数据库信息
SELECT name, open_mode, log_mode FROM v\$database;

-- 表空间使用情况
SELECT tablespace_name, 
       ROUND(used_space * 8 / 1024, 2) as used_gb,
       ROUND(tablespace_size * 8 / 1024, 2) as total_gb
FROM dba_tablespace_usage_metrics;

-- 会话数
SELECT COUNT(*) as active_sessions FROM v\$session WHERE status='ACTIVE';

-- 数据文件大小
SELECT SUM(bytes)/1024/1024/1024 as total_gb FROM dba_data_files;
EOF
    
    log_debug "统计信息已保存: $stats_file"
    echo "$stats_file"
}

# 全库备份
oracle_full_backup() {
    local output_dir="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$output_dir/oracle_full_${timestamp}.dmp"
    local log_file="$output_dir/expdp_${timestamp}.log"
    
    log_info "执行Oracle全库备份"
    
    _oracle_check_tools || return 1
    
    if [[ "$USE_EXPDP" == "true" ]]; then
        # 使用 expdp
        local directory_name="DATA_PUMP_DIR"
        local dump_name="oracle_full_${timestamp}.dmp"
        
        # 创建或获取DATA_PUMP_DIR
        local dp_dir=$(sqlplus -S "$(_oracle_connect_string)" <<EOF | grep -v "^$" | tail -1
SET PAGESIZE 0 FEEDBACK OFF
SELECT directory_path FROM dba_directories WHERE directory_name='DATA_PUMP_DIR';
EXIT;
EOF
)
        
        if [[ -z "$dp_dir" ]]; then
            log_warn "DATA_PUMP_DIR不存在，使用备用目录"
            dp_dir="$output_dir"
            sqlplus -S "$(_oracle_connect_string)" <<EOF
CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR AS '$dp_dir';
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO $ORACLE_USER;
EXIT;
EOF
        fi
        
        expdp "$(_oracle_connect_string)" \
            DIRECTORY=DATA_PUMP_DIR \
            DUMPFILE="$dump_name" \
            LOGFILE="$log_file" \
            FULL=Y \
            COMPRESSION=ALL \
            PARALLEL=4
        
        cp "$dp_dir/$dump_name" "$backup_file"
        cp "$dp_dir/$log_file" "$output_dir/"
    else
        # 使用传统exp
        exp "$(_oracle_connect_string)" \
            FILE="$backup_file" \
            LOG="$log_file" \
            FULL=Y \
            CONSISTENT=Y \
            COMPRESS=N
    fi
    
    if [[ -f "$backup_file" ]]; then
        log_success "Oracle全库备份完成: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "Oracle全库备份失败"
        return 1
    fi
}

# Schema备份
oracle_schema_backup() {
    local schema_name="$1"
    local output_dir="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$output_dir/oracle_schema_${schema_name}_${timestamp}.dmp"
    local log_file="$output_dir/expdp_${schema_name}_${timestamp}.log"
    
    log_info "备份Schema: $schema_name"
    
    _oracle_check_tools || return 1
    
    if [[ "$USE_EXPDP" == "true" ]]; then
        expdp "$(_oracle_connect_string)" \
            DIRECTORY=DATA_PUMP_DIR \
            DUMPFILE="schema_${schema_name}_${timestamp}.dmp" \
            LOGFILE="$log_file" \
            SCHEMAS="$schema_name" \
            COMPRESSION=ALL
        
        local dp_dir=$(sqlplus -S "$(_oracle_connect_string)" <<EOF
SET PAGESIZE 0 FEEDBACK OFF
SELECT directory_path FROM dba_directories WHERE directory_name='DATA_PUMP_DIR';
EXIT;
EOF
)
        cp "$dp_dir/schema_${schema_name}_${timestamp}.dmp" "$backup_file"
    else
        exp "$(_oracle_connect_string)" \
            FILE="$backup_file" \
            LOG="$log_file" \
            OWNER="$schema_name" \
            CONSISTENT=Y
    fi
    
    if [[ -f "$backup_file" ]]; then
        log_success "Schema备份完成: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "Schema备份失败: $schema_name"
        return 1
    fi
}

# 表备份
oracle_table_backup() {
    local table_name="$1"
    local output_dir="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$output_dir/oracle_table_${table_name}_${timestamp}.dmp"
    
    log_info "备份表: $table_name"
    
    # 使用exp导出单表
    exp "$(_oracle_connect_string)" \
        FILE="$backup_file" \
        TABLES="$table_name" \
        LOG="$output_dir/exp_${table_name}_${timestamp}.log"
    
    if [[ -f "$backup_file" ]]; then
        log_success "表备份完成: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "表备份失败: $table_name"
        return 1
    fi
}

# 清理归档日志
oracle_cleanup_archivelog() {
    local retention_days="${1:-7}"
    
    log_info "清理 ${retention_days} 天前的归档日志"
    
    sqlplus -S "$(_oracle_connect_string)" <<EOF
DELETE FROM ARCHIVED_LOG WHERE COMPLETION_TIME < SYSDATE - $retention_days;
EXIT;
EOF
}

# 恢复数据库
oracle_restore() {
    local backup_file="$1"
    local log_file="$2"
    
    log_info "恢复Oracle数据库: $backup_file"
    
    if [[ "$USE_EXPDP" == "true" ]]; then
        impdp "$(_oracle_connect_string)" \
            DIRECTORY=DATA_PUMP_DIR \
            DUMPFILE="$(basename "$backup_file")" \
            LOGFILE="$log_file" \
            FULL=Y
    else
        imp "$(_oracle_connect_string)" \
            FILE="$backup_file" \
            LOG="$log_file" \
            FULL=Y
    fi
}

# 模块主函数
database_main() {
    log_info "Oracle数据库模块就绪"
    log_info "实例: $ORACLE_HOST:$ORACLE_PORT/$ORACLE_SID"
    log_info "用户: $ORACLE_USER"
    
    if oracle_check_connection; then
        log_success "Oracle数据库连接正常"
        return 0
    else
        log_error "Oracle数据库连接异常"
        return 1
    fi
}

log_info "Oracle数据库模块加载完成"
