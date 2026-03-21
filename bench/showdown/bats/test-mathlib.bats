#!/usr/bin/env bats

SHOW_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
load "$SHOW_DIR/bats-libs/bats-support/load"
load "$SHOW_DIR/bats-libs/bats-assert/load"

setup() {
    source "$SHOW_DIR/lib/mathlib.sh"
}

# ── Basic arithmetic ─────────────────────────────────────────────────────────

@test "add returns sum of two numbers" {
    run math_add 3 4
    assert_output "7"
}

@test "sub returns difference" {
    run math_sub 12 7
    assert_output "5"
}

@test "mul returns product" {
    run math_mul 6 7
    assert_output "42"
}

@test "div returns integer quotient" {
    run math_div 10 3
    assert_output "3"
}

@test "mod returns remainder" {
    run math_mod 10 3
    assert_output "1"
}

@test "div by zero returns error" {
    run math_div 10 0
    assert_failure
}

@test "mod by zero returns error" {
    run math_mod 10 0
    assert_failure
}

# ── Absolute value, min, max, clamp ─────────────────────────────────────────

@test "abs of negative is positive" {
    run math_abs -42
    assert_output "42"
}

@test "abs of positive is unchanged" {
    run math_abs 7
    assert_output "7"
}

@test "max returns larger" {
    run math_max 3 9
    assert_output "9"
}

@test "min returns smaller" {
    run math_min 3 9
    assert_output "3"
}

@test "clamp within range is unchanged" {
    run math_clamp 5 1 10
    assert_output "5"
}

@test "clamp below range returns low" {
    run math_clamp -3 1 10
    assert_output "1"
}

@test "clamp above range returns high" {
    run math_clamp 99 1 10
    assert_output "10"
}

# ── Predicates ───────────────────────────────────────────────────────────────

@test "is_even: 4 is even" {
    run math_is_even 4
    assert_success
}

@test "is_even: 7 is not even" {
    run math_is_even 7
    assert_failure
}

@test "is_positive: 1 is positive" {
    run math_is_positive 1
    assert_success
}

@test "is_positive: -1 is not positive" {
    run math_is_positive -1
    assert_failure
}

@test "is_positive: 0 is not positive" {
    run math_is_positive 0
    assert_failure
}

# ── Numeric comparisons ─────────────────────────────────────────────────────

@test "factorial 5 = 120" {
    run math_factorial 5
    assert_output "120"
    [ "$output" -gt 100 ]
    [ "$output" -lt 200 ]
    [ "$output" -ge 120 ]
    [ "$output" -le 120 ]
}

@test "fibonacci 10 = 55" {
    run math_fibonacci 10
    assert_output "55"
    [ "$output" -gt 50 ]
    [ "$output" -le 100 ]
}

@test "factorial of negative fails" {
    run math_factorial -1
    assert_failure
}

# ── Edge cases ───────────────────────────────────────────────────────────────

@test "add with zero" {
    run math_add 0 0
    assert_output "0"
}

@test "fibonacci 0 = 0" {
    run math_fibonacci 0
    assert_output "0"
}

@test "fibonacci 1 = 1" {
    run math_fibonacci 1
    assert_output "1"
}

@test "factorial 0 = 1" {
    run math_factorial 0
    assert_output "1"
}
