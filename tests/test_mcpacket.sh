#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="${TMPDIR:-/tmp}/mcpacket_test_$$"
fake_bin="$test_dir/bin"
input_file="$test_dir/devicelist"
device_output="$test_dir/device.csv"
total_output="$test_dir/total.csv"
log_dir="$test_dir/log"
tmp_dir="$test_dir/tmp"
result_dir="$test_dir/result"

cleanup_test_output() {
	    rm -rf "$test_dir"
    }
trap cleanup_test_output EXIT

mkdir -p "$fake_bin" "$log_dir" "$tmp_dir" "$result_dir"

cat > "$fake_bin/ssh" <<'EOF'
#!/bin/sh
echo 100 120 20
EOF
chmod +x "$fake_bin/ssh"

cat > "$input_file" <<'EOF'
device_a
device_b
EOF

PATH="$fake_bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
LOG_BASE_DIR="$log_dir" \
TEMP_BASE_DIR="$tmp_dir" \
RESULT_BASE_DIR="$result_dir" \
MCPACKET_INPUT_FILE="$input_file" \
MCPACKET_DEVICE_OUTPUT_FILE="$device_output" \
MCPACKET_TOTAL_OUTPUT_FILE="$total_output" \
MCPACKET_TARGET_DATE=20260526 \
MCPACKET_TARGET_TIME=1900,1915 \
MCPACKET_MAX_PARALLEL=4 \
bash "$PROJECT_ROOT/run.sh" mcpacket >/dev/null

expected_device_rows=5
actual_device_rows="$(wc -l < "$device_output" | tr -d ' ')"
if [[ "$actual_device_rows" != "$expected_device_rows" ]]; then
    echo "Unexpected mcpacket device row count: $actual_device_rows" >&2
    exit 1
fi

if ! grep -q '^20260526,1900,200,240,40,16.6667%$' "$total_output"; then
    echo "Missing expected mcpacket 1900 aggregate row" >&2
    cat "$total_output" >&2
    exit 1
fi

if ! grep -q '^20260526,1915,200,240,40,16.6667%$' "$total_output"; then
    echo "Missing expected mcpacket 1915 aggregate row" >&2
    cat "$total_output" >&2
    exit 1
fi

echo "mcpacket test passed"
