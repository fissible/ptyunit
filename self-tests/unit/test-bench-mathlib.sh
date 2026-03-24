#!/usr/bin/env bash
# Note: assert_output/assert_true/assert_false suppress stderr (2>/dev/null),
# which swallows the PS4 trace. Call functions directly — result=$(...) traces
# the function body; direct predicate calls + $? check also trace correctly.
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"
source "$PTYUNIT_DIR/bench/showdown/lib/mathlib.sh"

# ── Basic arithmetic ─────────────────────────────────────────────────────────

test_that "add returns sum of two numbers"
result=$(math_add 3 4)
assert_eq "7" "$result"

test_that "sub returns difference"
result=$(math_sub 12 7)
assert_eq "5" "$result"

test_that "mul returns product"
result=$(math_mul 6 7)
assert_eq "42" "$result"

test_that "div returns integer quotient"
result=$(math_div 10 3)
assert_eq "3" "$result"

test_that "mod returns remainder"
result=$(math_mod 10 3)
assert_eq "1" "$result"

test_that "div by zero returns error"
math_div 10 0
assert_not_eq "0" "$?"

test_that "mod by zero returns error"
math_mod 10 0
assert_not_eq "0" "$?"

# ── Absolute value, min, max, clamp ─────────────────────────────────────────

test_that "abs of negative is positive"
result=$(math_abs -42)
assert_eq "42" "$result"

test_that "abs of positive is unchanged"
result=$(math_abs 7)
assert_eq "7" "$result"

test_that "max returns larger"
result=$(math_max 3 9)
assert_eq "9" "$result"

test_that "max when first arg is larger"
result=$(math_max 9 3)
assert_eq "9" "$result"

test_that "min returns smaller"
result=$(math_min 3 9)
assert_eq "3" "$result"

test_that "min when second arg is smaller"
result=$(math_min 9 3)
assert_eq "3" "$result"

test_that "clamp within range is unchanged"
result=$(math_clamp 5 1 10)
assert_eq "5" "$result"

test_that "clamp below range returns low"
result=$(math_clamp -3 1 10)
assert_eq "1" "$result"

test_that "clamp above range returns high"
result=$(math_clamp 99 1 10)
assert_eq "10" "$result"

# ── Predicates ───────────────────────────────────────────────────────────────

test_that "is_even: 4 is even"
math_is_even 4
assert_eq "0" "$?"

test_that "is_even: 7 is not even"
math_is_even 7
assert_not_eq "0" "$?"

test_that "is_positive: 1 is positive"
math_is_positive 1
assert_eq "0" "$?"

test_that "is_positive: -1 is not positive"
math_is_positive -1
assert_not_eq "0" "$?"

test_that "is_positive: 0 is not positive"
math_is_positive 0
assert_not_eq "0" "$?"

# ── Factorial and fibonacci ───────────────────────────────────────────────────

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
math_factorial -1
assert_not_eq "0" "$?"

test_that "fibonacci of negative fails"
math_fibonacci -1
assert_not_eq "0" "$?"

# ── Edge cases ───────────────────────────────────────────────────────────────

test_that "add with zero"
result=$(math_add 0 0)
assert_eq "0" "$result"

test_that "fibonacci 0 = 0"
result=$(math_fibonacci 0)
assert_eq "0" "$result"

test_that "fibonacci 1 = 1"
result=$(math_fibonacci 1)
assert_eq "1" "$result"

test_that "factorial 0 = 1"
result=$(math_factorial 0)
assert_eq "1" "$result"

ptyunit_test_summary
