#!/usr/bin/env bash
# Note: assert_output/assert_true/assert_false suppress stderr (2>/dev/null),
# which swallows the PS4 trace. Call functions directly — result=$(...) traces
# the function body; direct predicate calls + $? check also trace correctly.
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"
source "$PTYUNIT_DIR/bench/showdown/lib/configlib.sh"

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

# ── config_get ───────────────────────────────────────────────────────────────

test_that "config_get reads server host"
result=$(config_get "$_cfg" "server" "host")
assert_eq "localhost" "$result"

test_that "config_get reads server port"
result=$(config_get "$_cfg" "server" "port")
assert_eq "8080" "$result"

test_that "config_get reads database name"
result=$(config_get "$_cfg" "database" "name")
assert_eq "myapp" "$result"

test_that "config_get: missing key fails"
config_get "$_cfg" "server" "nonexistent"
assert_not_eq "0" "$?"

test_that "config_get: missing section fails"
config_get "$_cfg" "nosection" "key"
assert_not_eq "0" "$?"

test_that "config_get: missing file fails"
config_get "/no/such/file" "s" "k"
assert_not_eq "0" "$?"

# ── config_sections ──────────────────────────────────────────────────────────

test_that "config_sections lists all sections"
result=$(config_sections "$_cfg")
assert_line "server" 1 "$result"
assert_line "database" 2 "$result"
assert_contains "$result" "server"
assert_contains "$result" "database"
assert_not_contains "$result" "missing"

test_that "config_sections: missing file fails"
config_sections "/no/such/file"
assert_not_eq "0" "$?"

# ── config_keys ──────────────────────────────────────────────────────────────

test_that "config_keys lists keys in section"
result=$(config_keys "$_cfg" "database")
assert_contains "$result" "host"
assert_contains "$result" "port"
assert_contains "$result" "name"
assert_contains "$result" "user"

test_they "keys do not bleed across sections"
result=$(config_keys "$_cfg" "server")
assert_not_contains "$result" "name"
assert_not_contains "$result" "user"

test_that "config_keys: missing file fails"
config_keys "/no/such/file" "server"
assert_not_eq "0" "$?"

# ── config_has_section / config_has_key ──────────────────────────────────────

test_that "has_section finds existing section"
config_has_section "$_cfg" "server"
assert_eq "0" "$?"

test_that "has_section rejects missing section"
config_has_section "$_cfg" "nosection"
assert_not_eq "0" "$?"

test_that "has_section: missing file fails"
config_has_section "/no/such/file" "server"
assert_not_eq "0" "$?"

test_that "has_key finds existing key"
config_has_key "$_cfg" "database" "host"
assert_eq "0" "$?"

test_that "has_key rejects missing key"
config_has_key "$_cfg" "database" "password"
assert_not_eq "0" "$?"

# ── config_validate ──────────────────────────────────────────────────────────

test_that "validate: well-formed config passes"
config_validate "$_cfg"
assert_eq "0" "$?"

test_that "validate: malformed config fails"
printf '[section]\nbad line\n' > "$_ws/bad.ini"
config_validate "$_ws/bad.ini"
assert_not_eq "0" "$?"

test_that "validate: reports syntax error"
printf '[section]\nbad line\n' > "$_ws/bad2.ini"
result=$(config_validate "$_ws/bad2.ini" 2>&1)
assert_match "syntax error" "$result"

test_that "validate: missing file fails"
result=$(config_validate "/no/such/file" 2>&1)
config_validate "/no/such/file"
assert_not_eq "0" "$?"
assert_match "file not found" "$result"

# ── assert_file_exists on config ─────────────────────────────────────────────

test_that "config file exists after setup"
assert_file_exists "$_cfg"

# ── assert_not_null for config values ────────────────────────────────────────

test_that "config values are non-empty"
val=$(config_get "$_cfg" "server" "host")
assert_not_null "$val"

# ── Per-test skip ─────────────────────────────────────────────────────────────

test_that "skip: platform-conditional test"
ptyunit_skip_test "demonstrating per-test skip"
assert_eq "never" "reached"

test_that "assertions resume after skip"
assert_eq "ok" "ok"

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
