#!/bin/bash
# modules/backup/main.sh - 备份模块

# 模块配置
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# 模块私有函数
_compress_backup() {
    local source="$1"
    local target="$2"
    log_debug "压缩: $source -> $target"
    tar -czf "$target" -C "$(dirname "$source")" "$(basename "$source")"
}

_cleanup_old_backups() {
    log_info "清理 ${RETENTION_DAYS} 天前的备份"
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
}

# 模块清理函数
cleanup_backup() {
    log_info "清理备份模块临时文件"
    local temp_dir="$TEMP_BASE_DIR/backup"
    safe_rm_dir "$temp_dir"
}

# 模块公有函数
backup_create() {
    local name="$1"
    local source="$2"
    
    log_info "创建备份: $name"
    
    mkdir -p "$BACKUP_DIR"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/${name}_${timestamp}.tar.gz"
    
    _compress_backup "$source" "$backup_file"
    _cleanup_old_backups
    
    log_success "备份创建成功: $backup_file"
    echo "$backup_file"
}

backup_list() {
    log_info "列出备份文件"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "无备份文件"
}

# 模块主函数
backup_main() {
    log_info "备份模块启动"
    
    mkdir -p "$BACKUP_DIR"
    log_info "备份目录: $BACKUP_DIR"
    log_info "保留天数: $RETENTION_DAYS"
    
    backup_list
    
    log_info "备份模块就绪"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_environment "backup"
    backup_main
fi
