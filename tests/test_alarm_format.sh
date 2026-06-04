#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_file="${TMPDIR:-/tmp}/alarm_format_test_$$.csv"

cleanup_test_output() {
    rm -f "$output_file"
}
trap cleanup_test_output EXIT

source "$PROJECT_ROOT/lib/core.sh"
RUN_TS="test"
RUN_ID="test_$$"
MODULE_NAME="alarm_format"
export RUN_TS RUN_ID MODULE_NAME
load_config global
init_paths
ensure_module_dirs alarm_format
source "$PROJECT_ROOT/modules/alarm_format/module.sh"

input_file="$PROJECT_ROOT/modules/alarm_format/data/devicelist"
module_run "$input_file" "$output_file"

expected_first_line="xxx,xxx,xxx,xxx,xxx"
actual_first_line="$(head -n 1 "$output_file")"
actual_count="$(wc -l < "$output_file" | tr -d ' ')"

if [[ "$actual_first_line" != "$expected_first_line" ]]; then
    echo "Unexpected first formatted line" >&2
    echo "Expected: $expected_first_line" >&2
    echo "Actual:   $actual_first_line" >&2
    exit 1
fi

if [[ "$actual_count" != "28" ]]; then
    echo "Unexpected formatted row count: $actual_count" >&2
    exit 1
fi

echo "alarm_format test passed"
