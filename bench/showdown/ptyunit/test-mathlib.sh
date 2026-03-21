#!/usr/bin/env bash
set -u
SHOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PTYUNIT_DIR="$(cd "$SHOW_DIR/../.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"
source "$SHOW_DIR/lib/mathlib.sh"

# ── Basic arithmetic (assert_eq, assert_output) ─────────────────────────────

test_that "add returns sum of two numbers"
assert_output "7" math_add 3 4

test_that "sub returns difference"
assert_output "5" math_sub 12 7

test_that "mul returns product"
assert_output "42" math_mul 6 7

test_that "div returns integer quotient"
assert_output "3" math_div 10 3

test_that "mod returns remainder"
assert_output "1" math_mod 10 3

test_that "div by zero returns error"
assert_false math_div 10 0

test_that "mod by zero returns error"
assert_false math_mod 10 0

# ── Absolute value, min, max, clamp ─────────────────────────────────────────

test_that "abs of negative is positive"
assert_output "42" math_abs -42

test_that "abs of positive is unchanged"
assert_output "7" math_abs 7

test_that "max returns larger"
assert_output "9" math_max 3 9

test_that "min returns smaller"
assert_output "3" math_min 3 9

test_that "clamp within range is unchanged"
assert_output "5" math_clamp 5 1 10

test_that "clamp below range returns low"
assert_output "1" math_clamp -3 1 10

test_that "clamp above range returns high"
assert_output "10" math_clamp 99 1 10

# ── Predicates (assert_true, assert_false) ───────────────────────────────────

test_that "is_even: 4 is even"
assert_true math_is_even 4

test_that "is_even: 7 is not even"
assert_false math_is_even 7

test_that "is_positive: 1 is positive"
assert_true math_is_positive 1

test_that "is_positive: -1 is not positive"
assert_false math_is_positive -1

test_that "is_positive: 0 is not positive"
assert_false math_is_positive 0

# ── Numeric comparisons (assert_gt, assert_lt, assert_ge, assert_le) ────────

test_that "factorial 5 = 120"
result=$(math_factorial 5)
assert_eq "120" "$result"
assert_gt "$result" 100
assert_lt "$result" 200
assert_ge "$result" 120
assert_le "$result" 120

test_that "fibonacci 10 = 55"
result=$(math_fibonacci 10)
assert_eq "55" "$result"
assert_gt "$result" 50
assert_le "$result" 100

test_that "factorial of negative fails"
assert_false math_factorial -1

# ── Edge cases ───────────────────────────────────────────────────────────────

test_that "add with zero"
assert_output "0" math_add 0 0

test_that "fibonacci 0 = 0"
assert_output "0" math_fibonacci 0

test_that "fibonacci 1 = 1"
assert_output "1" math_fibonacci 1

test_that "factorial 0 = 1"
assert_output "1" math_factorial 0

ptyunit_test_summary
