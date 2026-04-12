echo "Running tests with coverage..."

JSON_FILE="$OTTO_TASK_DIR/coverage.json"

TEST_FAILED=0
if ! cargo llvm-cov --all-features --json --output-path "$JSON_FILE" 2>&1; then
  TEST_FAILED=1
fi

if [ ! -s "$JSON_FILE" ] || ! jq -e '.data[0].totals' "$JSON_FILE" >/dev/null 2>&1; then
  echo "Tests failed - no coverage data generated"
  exit 1
fi

cargo llvm-cov report --html --output-dir target/llvm-cov/html >/dev/null 2>&1 || true

otto_set_output "json_path" "$JSON_FILE"
otto_set_output "test_failed" "$TEST_FAILED"
otto_set_output "lines_pct" "$(jq -r '.data[0].totals.lines.percent // 0' "$JSON_FILE")"
otto_set_output "lines_cov" "$(jq -r '.data[0].totals.lines.covered // 0' "$JSON_FILE")"
otto_set_output "lines_tot" "$(jq -r '.data[0].totals.lines.count // 0' "$JSON_FILE")"
otto_set_output "funcs_pct" "$(jq -r '.data[0].totals.functions.percent // 0' "$JSON_FILE")"
otto_set_output "funcs_cov" "$(jq -r '.data[0].totals.functions.covered // 0' "$JSON_FILE")"
otto_set_output "funcs_tot" "$(jq -r '.data[0].totals.functions.count // 0' "$JSON_FILE")"
otto_set_output "regions_pct" "$(jq -r '.data[0].totals.regions.percent // 0' "$JSON_FILE")"
