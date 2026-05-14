#!/bin/bash
# scripts/common.sh - 通用业务函数

# 检查是否被正确加载
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "错误: 此脚本应该被 source 调用" >&2
    exit 1
fi

# 验证数据完整性
validate_data() {
    local file="$1"
    local expected_size="${2:-1}"
    
    if [[ ! -f "$file" ]]; then
        log_error "文件不存在: $file"
        return 1
    fi
    
    local actual_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    if [[ $actual_size -lt $expected_size ]]; then
        log_error "文件太小: $file (${actual_size} bytes)"
        return 1
    fi
    
    log_debug "数据验证通过: $file"
    return 0
}

# 验证Oracle导出文件
validate_oracle_dump() {
    local dump_file="$1"
    
    if [[ ! -f "$dump_file" ]]; then
        log_error "Oracle dump文件不存在: $dump_file"
        return 1
    fi
    
    # 检查文件头（Oracle dump文件通常以"EXP"或"EXPORT"开头）
    if file "$dump_file" | grep -qi "oracle"; then
        log_debug "Oracle dump文件验证通过: $dump_file"
        return 0
    else
        log_warn "文件可能不是有效的Oracle dump: $dump_file"
        return 0  # 不强制失败，只警告
    fi
}

# 发送通知
send_notification() {
    local subject="$1"
    local message="$2"
    local webhook="${WEBHOOK_URL:-}"
    
    log_info "通知: $subject"
    
    if [[ -n "$webhook" ]]; then
        curl -X POST -H "Content-Type: application/json" \
            -d "{\"text\":\"[$MODULE_NAME] $subject\n$message\"}" \
            "$webhook" 2>/dev/null || true
    fi
}

# 等待Oracle服务就绪
wait_for_oracle() {
    local host="$1"
    local port="${2:-1521}"
    local timeout="${3:-60}"
    local start_time=$(date +%s)
    
    log_info "等待Oracle服务就绪: $host:$port"
    
    while ! nc -z "$host" "$port" 2>/dev/null; do
        if [[ $(($(date +%s) - start_time)) -gt $timeout ]]; then
            log_error "Oracle服务超时: $host:$port"
            return 1
        fi
        sleep 2
    done
    
    log_success "Oracle服务就绪: $host:$port"
    return 0
}

# 执行SQL*Plus查询
run_sqlplus_query() {
    local sql="$1"
    local output_file="$2"
    
    sqlplus -S "${ORACLE_USER}/${ORACLE_PASS}@${ORACLE_HOST}:${ORACLE_PORT}/${ORACLE_SID}" <<EOF > "$output_file" 2>&1
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
$sql
EXIT;
EOF
    
    return $?
}
