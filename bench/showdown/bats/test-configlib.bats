#!/usr/bin/env bats

SHOW_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
load "$SHOW_DIR/bats-libs/bats-support/load"
load "$SHOW_DIR/bats-libs/bats-assert/load"

setup() {
    source "$SHOW_DIR/lib/configlib.sh"
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

teardown() {
    [[ -n "${_ws:-}" ]] && rm -rf "$_ws"
}

# ── config_get ───────────────────────────────────────────────────────────────

@test "config_get reads server host" {
    run config_get "$_cfg" "server" "host"
    assert_output "localhost"
}

@test "config_get reads server port" {
    run config_get "$_cfg" "server" "port"
    assert_output "8080"
}

@test "config_get reads database name" {
    run config_get "$_cfg" "database" "name"
    assert_output "myapp"
}

@test "config_get: missing key fails" {
    run config_get "$_cfg" "server" "nonexistent"
    assert_failure
}

@test "config_get: missing section fails" {
    run config_get "$_cfg" "nosection" "key"
    assert_failure
}

@test "config_get: missing file fails" {
    run config_get "/no/such/file" "s" "k"
    assert_failure
}

# ── config_sections ──────────────────────────────────────────────────────────

@test "config_sections lists all sections" {
    run config_sections "$_cfg"
    assert_line -n 0 "server"
    assert_line -n 1 "database"
    assert_output --partial "server"
    assert_output --partial "database"
    refute_output --partial "missing"
}

# ── config_keys ──────────────────────────────────────────────────────────────

@test "config_keys lists keys in section" {
    run config_keys "$_cfg" "database"
    assert_output --partial "host"
    assert_output --partial "port"
    assert_output --partial "name"
    assert_output --partial "user"
}

@test "keys do not bleed across sections" {
    run config_keys "$_cfg" "server"
    refute_output --partial "name"
    refute_output --partial "user"
}

# ── config_has_section / config_has_key ──────────────────────────────────────

@test "has_section finds existing section" {
    run config_has_section "$_cfg" "server"
    assert_success
}

@test "has_section rejects missing section" {
    run config_has_section "$_cfg" "nosection"
    assert_failure
}

@test "has_key finds existing key" {
    run config_has_key "$_cfg" "database" "host"
    assert_success
}

@test "has_key rejects missing key" {
    run config_has_key "$_cfg" "database" "password"
    assert_failure
}

# ── config_validate ──────────────────────────────────────────────────────────

@test "validate: well-formed config passes" {
    run config_validate "$_cfg"
    assert_success
}

@test "validate: malformed config fails" {
    printf '[section]\nbad line\n' > "$_ws/bad.ini"
    run config_validate "$_ws/bad.ini"
    assert_failure
}

@test "validate: reports syntax error" {
    printf '[section]\nbad line\n' > "$_ws/bad2.ini"
    run config_validate "$_ws/bad2.ini"
    assert_output --partial "syntax error"
}

# ── assert_file_exists on config ─────────────────────────────────────────────

@test "config file exists after setup" {
    [ -f "$_cfg" ]
}

# ── assert_not_null for config values ────────────────────────────────────────

@test "config values are non-empty" {
    local val
    val=$(config_get "$_cfg" "server" "host")
    [ -n "$val" ]
}

# ── Per-test skip ────────────────────────────────────────────────────────────

@test "skip: platform-conditional test" {
    skip "demonstrating per-test skip"
    [ "never" = "reached" ]
}

@test "assertions resume after skip" {
    [ "ok" = "ok" ]
}

# ── All values match expected pattern ────────────────────────────────────────

@test "all values match expected pattern" {
    for section in server database; do
        local val
        val=$(config_get "$_cfg" "$section" "host")
        [[ "$val" =~ [a-z] ]]
    done
}

# ── Numeric assertions on config values ──────────────────────────────────────

@test "server port is in valid range" {
    local port
    port=$(config_get "$_cfg" "server" "port")
    [ "$port" -gt 0 ]
    [ "$port" -le 65535 ]
}

@test "database port is standard PostgreSQL port" {
    local port
    port=$(config_get "$_cfg" "database" "port")
    [ "$port" = "5432" ]
    [ "$port" -ge 1024 ]
}
