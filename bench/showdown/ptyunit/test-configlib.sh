#!/usr/bin/env bash
set -u
SHOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$SHOW_DIR/../.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"
source "$SHOW_DIR/lib/configlib.sh"

# ── Per-test setup/teardown ──────────────────────────────────────────────────
_ws=""
_cfg=""
ptyunit_setup() {
    _ws=$(mktemp -d)
    _cfg="$_ws/test.ini"
    cat > "$_cfg" << 'INI'
# Application config
[server]
host = localhost
port = 8080
debug = true

; Database settings
[database]
host = db.example.com
port = 5432
name = myapp
user = admin
INI
}
ptyunit_teardown() {
    [[ -n "$_ws" ]] && rm -rf "$_ws"
}

# ── config_get (assert_eq, assert_output) ────────────────────────────────────

test_that "config_get reads server host"
assert_output "localhost" config_get "$_cfg" "server" "host"

test_that "config_get reads server port"
assert_output "8080" config_get "$_cfg" "server" "port"

test_that "config_get reads database name"
assert_output "myapp" config_get "$_cfg" "database" "name"

test_that "config_get: missing key fails"
assert_false config_get "$_cfg" "server" "nonexistent"

test_that "config_get: missing section fails"
assert_false config_get "$_cfg" "nosection" "key"

test_that "config_get: missing file fails"
assert_false config_get "/no/such/file" "s" "k"

# ── config_sections (assert_line, assert_contains) ───────────────────────────

test_that "config_sections lists all sections"
result=$(config_sections "$_cfg")
assert_line "server" 1 "$result"
assert_line "database" 2 "$result"
assert_contains "$result" "server"
assert_contains "$result" "database"
assert_not_contains "$result" "missing"

# ── config_keys ──────────────────────────────────────────────────────────────

test_that "config_keys lists keys in section"
result=$(config_keys "$_cfg" "database")
assert_contains "$result" "host"
assert_contains "$result" "port"
assert_contains "$result" "name"
assert_contains "$result" "user"

test_they "do not bleed across sections"
result=$(config_keys "$_cfg" "server")
assert_not_contains "$result" "name"
assert_not_contains "$result" "user"

# ── config_has_section / config_has_key ──────────────────────────────────────

test_that "has_section finds existing section"
assert_true config_has_section "$_cfg" "server"

test_that "has_section rejects missing section"
assert_false config_has_section "$_cfg" "nosection"

test_that "has_key finds existing key"
assert_true config_has_key "$_cfg" "database" "host"

test_that "has_key rejects missing key"
assert_false config_has_key "$_cfg" "database" "password"

# ── config_validate ──────────────────────────────────────────────────────────

test_that "validate: well-formed config passes"
assert_true config_validate "$_cfg"

test_that "validate: malformed config fails"
printf '[section]\nbad line\n' > "$_ws/bad.ini"
assert_false config_validate "$_ws/bad.ini"

test_that "validate: reports syntax error"
printf '[section]\nbad line\n' > "$_ws/bad2.ini"
result=$(config_validate "$_ws/bad2.ini" 2>&1)
assert_match "syntax error" "$result"

# ── assert_file_exists on config ─────────────────────────────────────────────

test_that "config file exists after setup"
assert_file_exists "$_cfg"

# ── assert_not_null for config values ────────────────────────────────────────

test_that "config values are non-empty"
val=$(config_get "$_cfg" "server" "host")
assert_not_null "$val"

# ── Per-test skip (ptyunit_skip_test) ────────────────────────────────────────

test_that "skip: platform-conditional test"
ptyunit_skip_test "demonstrating per-test skip"
# These assertions should be silently skipped
assert_eq "never" "reached"

test_that "assertions resume after skip"
assert_eq "ok" "ok"

# ── test_they alias works ────────────────────────────────────────────────────

test_they "all values match expected pattern"
for section in server database; do
    val=$(config_get "$_cfg" "$section" "host")
    assert_match "[a-z]" "$val"
done

# ── Numeric assertions on config values ──────────────────────────────────────

test_that "server port is in valid range"
port=$(config_get "$_cfg" "server" "port")
assert_gt "$port" 0
assert_le "$port" 65535

test_that "database port is standard PostgreSQL port"
port=$(config_get "$_cfg" "database" "port")
assert_eq "5432" "$port"
assert_ge "$port" 1024

ptyunit_test_summary
