#!/bin/bash
# modules/backup/main.sh - 备份模块（支持Oracle备份管理）

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "错误: 此脚本应该被 source 调用" >&2
    exit 1
fi

log_info "备份模块加载中..."

BACKUP_RETENTION="${BACKUP_RETENTION:-7}"
BACKUP_DIR="${BACKUP_DIR:-$BACKUPS_DIR}"

cleanup_backup() {
    log_info "清理备份模块"
    safe_rm_dir "$TEMP_BASE_DIR/backup"
}

# 创建备份
backup_create() {
    local name="$1"
    local source="$2"
    local backup_file="$BACKUP_DIR/${name}_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    log_info "创建备份: $name"
    
    if [[ -d "$source" ]]; then
        tar -czf "$backup_file" -C "$(dirname "$source")" "$(basename "$source")" 2>/dev/null
    elif [[ -f "$source" ]]; then
        tar -czf "$backup_file" -C "$(dirname "$source")" "$(basename "$source")" 2>/dev/null
    else
        log_error "备份源不存在: $source"
        return 1
    fi
    
    if [[ -f "$backup_file" ]]; then
        log_success "备份创建: $backup_file ($(du -h "$backup_file" | cut -f1))"
        echo "$backup_file"
        return 0
    else
        log_error "备份创建失败"
        return 1
    fi
}

# 恢复备份
backup_restore() {
    local backup_file="$1"
    local restore_dir="$2"
    
    log_info "恢复备份: $backup_file -> $restore_dir"
    
    mkdir -p "$restore_dir"
    tar -xzf "$backup_file" -C "$restore_dir"
    
    log_success "备份恢复完成"
}

# 列出备份
backup_list() {
    log_info "列出备份文件"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print $9 " (" $5 ")"}' || echo "  无备份文件"
    else
        echo "  备份目录不存在"
    fi
}

# 清理旧备份
backup_cleanup_old() {
    local retention_days="${1:-$BACKUP_RETENTION}"
    
    log_info "清理 ${retention_days} 天前的备份"
    
    local cleaned=$(find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$retention_days -delete -print 2>/dev/null | wc -l)
    log_debug "清理了 ${cleaned} 个旧备份"
}

# 验证备份完整性
backup_verify() {
    local backup_file="$1"
    
    log_info "验证备份: $backup_file"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在"
        return 1
    fi
    
    # 测试tar文件完整性
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_success "备份验证通过: $backup_file"
        return 0
    else
        log_error "备份验证失败: $backup_file"
        return 1
    fi
}

# 模块主函数
backup_main() {
    log_info "备份模块就绪"
    log_info "备份目录: $BACKUP_DIR"
    log_info "保留天数: $BACKUP_RETENTION"
    
    mkdir -p "$BACKUP_DIR"
    
    # 显示现有备份数量
    local backup_count=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f 2>/dev/null | wc -l)
    log_info "现有备份数: $backup_count"
}

log_info "备份模块加载完成"
