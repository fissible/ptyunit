#!/usr/bin/env bats

SHOW_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
load "$SHOW_DIR/bats-libs/bats-support/load"
load "$SHOW_DIR/bats-libs/bats-assert/load"

setup() {
    source "$SHOW_DIR/lib/strlib.sh"
}

# ── Case conversion ─────────────────────────────────────────────────────────

@test "upper converts to uppercase" {
    run str_upper "hello world"
    assert_output "HELLO WORLD"
}

@test "lower converts to lowercase" {
    run str_lower "HELLO WORLD"
    assert_output "hello world"
}

@test "upper is idempotent" {
    local result
    result=$(str_upper "$(str_upper "abc")")
    [ "$result" = "ABC" ]
}

# ── Trimming ─────────────────────────────────────────────────────────────────

@test "trim removes leading and trailing whitespace" {
    run str_trim "  hello  "
    assert_output "hello"
}

@test "trim handles tabs" {
    run str_trim $'\t hello \t'
    assert_output "hello"
}

# ── Length and repeat ────────────────────────────────────────────────────────

@test "len returns string length" {
    run str_len "hello"
    assert_output "5"
}

@test "len of empty string is 0" {
    run str_len ""
    assert_output "0"
}

@test "repeat builds repeated string" {
    run str_repeat "abc" 3
    assert_output "abcabcabc"
}

@test "repeat 0 returns empty" {
    run str_repeat "abc" 0
    assert_output ""
}

# ── Reverse ──────────────────────────────────────────────────────────────────

@test "reverse reverses a string" {
    run str_reverse "abcd"
    assert_output "dcba"
}

@test "reverse of palindrome is unchanged" {
    run str_reverse "racecar"
    assert_output "racecar"
}

# ── Contains / starts / ends ─────────────────────────────────────────────────

@test "contains finds substring" {
    run str_contains "hello world" "world"
    assert_success
}

@test "contains rejects missing substring" {
    run str_contains "hello world" "xyz"
    assert_failure
}

@test "starts_with matches prefix" {
    run str_starts_with "hello world" "hello"
    assert_success
}

@test "ends_with matches suffix" {
    run str_ends_with "hello world" "world"
    assert_success
}

@test "starts_with rejects non-prefix" {
    run str_starts_with "hello world" "world"
    assert_failure
}

# ── Empty check ──────────────────────────────────────────────────────────────

@test "is_empty: empty string returns true" {
    run str_is_empty ""
    assert_success
}

@test "is_empty: non-empty string returns false" {
    run str_is_empty "x"
    assert_failure
}

@test "not_null for non-empty result" {
    local result
    result=$(str_upper "hi")
    [ -n "$result" ]
}

@test "null for empty repeat" {
    local result
    result=$(str_repeat "x" 0)
    [ -z "$result" ]
}

# ── Replace ──────────────────────────────────────────────────────────────────

@test "replace substitutes all occurrences" {
    run str_replace "hello world" "o" "-"
    assert_output "hell- w-rld"
}

@test "replace with empty removes occurrences" {
    run str_replace "hello world" "o" ""
    assert_output "hell wrld"
}

# ── Line operations ──────────────────────────────────────────────────────────

@test "count_lines counts correctly" {
    run str_count_lines $'line1\nline2\nline3'
    assert_output "3"
}

@test "get_line returns correct line" {
    run str_get_line $'alpha\nbeta\ngamma' 2
    assert_output "beta"
}

@test "assert_line checks line content" {
    local text=$'first\nsecond\nthird'
    run printf '%s' "$text"
    assert_line -n 0 "first"
    assert_line -n 1 "second"
    assert_line -n 2 "third"
}

# ── Join / Split ─────────────────────────────────────────────────────────────

@test "join combines with separator" {
    run str_join "," "a" "b" "c"
    assert_output "a,b,c"
}

@test "join with single item" {
    run str_join "," "only"
    assert_output "only"
}

@test "split_first returns before delimiter" {
    run str_split_first "hello:world" ":"
    assert_output "hello"
}

@test "split_last returns after delimiter" {
    run str_split_last "hello:world" ":"
    assert_output "world"
}

# ── Regex match ──────────────────────────────────────────────────────────────

@test "email-like pattern matches" {
    local email="user@example.com"
    [[ "$email" =~ [a-z]+@[a-z]+\.[a-z]+ ]]
}

@test "version pattern matches semver-like" {
    local version="v1.2.3"
    [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "upper result matches all-caps pattern" {
    local result
    result=$(str_upper "hello")
    [[ "$result" =~ ^[A-Z]+$ ]]
}

# ── Multi-line output ────────────────────────────────────────────────────────

@test "words splits into lines" {
    run str_words "hello world foo"
    assert_line -n 0 "hello"
    assert_line -n 1 "world"
    assert_line -n 2 "foo"
    assert_output --partial "world"
    refute_output --partial "bar"
}
