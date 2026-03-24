#!/usr/bin/env bash
# Note: assert_output/assert_true/assert_false suppress stderr (2>/dev/null),
# which swallows the PS4 trace. Call functions directly — result=$(...) traces
# the function body; direct predicate calls + $? check also trace correctly.
set -u
PTYUNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$PTYUNIT_DIR/assert.sh"
source "$PTYUNIT_DIR/bench/showdown/lib/strlib.sh"

# ── Case conversion ──────────────────────────────────────────────────────────

test_that "upper converts to uppercase"
result=$(str_upper "hello world")
assert_eq "HELLO WORLD" "$result"

test_that "lower converts to lowercase"
result=$(str_lower "HELLO WORLD")
assert_eq "hello world" "$result"

test_that "upper is idempotent"
result=$(str_upper "abc")
result=$(str_upper "$result")
assert_eq "ABC" "$result"

# ── Trimming ─────────────────────────────────────────────────────────────────

test_that "trim removes leading and trailing whitespace"
result=$(str_trim "  hello  ")
assert_eq "hello" "$result"

test_that "trim handles tabs"
result=$(str_trim $'\t hello \t')
assert_eq "hello" "$result"

# ── Length and repeat ────────────────────────────────────────────────────────

test_that "len returns string length"
result=$(str_len "hello")
assert_eq "5" "$result"

test_that "len of empty string is 0"
result=$(str_len "")
assert_eq "0" "$result"

test_that "repeat builds repeated string"
result=$(str_repeat "abc" 3)
assert_eq "abcabcabc" "$result"

test_that "repeat 0 returns empty"
result=$(str_repeat "abc" 0)
assert_null "$result"

# ── Reverse ──────────────────────────────────────────────────────────────────

test_that "reverse reverses a string"
result=$(str_reverse "abcd")
assert_eq "dcba" "$result"

test_that "reverse of palindrome is unchanged"
result=$(str_reverse "racecar")
assert_eq "racecar" "$result"

# ── Contains / starts / ends ─────────────────────────────────────────────────

test_that "contains finds substring"
str_contains "hello world" "world"
assert_eq "0" "$?"

test_that "contains rejects missing substring"
str_contains "hello world" "xyz"
assert_not_eq "0" "$?"

test_that "starts_with matches prefix"
str_starts_with "hello world" "hello"
assert_eq "0" "$?"

test_that "starts_with rejects non-prefix"
str_starts_with "hello world" "world"
assert_not_eq "0" "$?"

test_that "ends_with matches suffix"
str_ends_with "hello world" "world"
assert_eq "0" "$?"

test_that "ends_with rejects non-suffix"
str_ends_with "hello world" "hello"
assert_not_eq "0" "$?"

# ── Empty check ──────────────────────────────────────────────────────────────

test_that "is_empty: empty string returns true"
str_is_empty ""
assert_eq "0" "$?"

test_that "is_empty: non-empty string returns false"
str_is_empty "x"
assert_not_eq "0" "$?"

test_that "not_null for non-empty result"
result=$(str_upper "hi")
assert_not_null "$result"

test_that "null for empty repeat"
result=$(str_repeat "x" 0)
assert_null "$result"

# ── Replace ──────────────────────────────────────────────────────────────────

test_that "replace substitutes all occurrences"
result=$(str_replace "hello world" "o" "-")
assert_eq "hell- w-rld" "$result"

test_that "replace with empty removes occurrences"
result=$(str_replace "hello world" "o" "")
assert_eq "hell wrld" "$result"

# ── Line operations ──────────────────────────────────────────────────────────

test_that "count_lines counts correctly"
text=$'line1\nline2\nline3'
result=$(str_count_lines "$text")
assert_eq "3" "$result"

test_that "get_line returns correct line"
text=$'alpha\nbeta\ngamma'
result=$(str_get_line "$text" 2)
assert_eq "beta" "$result"

test_that "get_line: out of range returns failure"
text=$'alpha\nbeta'
str_get_line "$text" 5
assert_not_eq "0" "$?"

test_that "assert_line checks line content"
text=$'first\nsecond\nthird'
assert_line "first" 1 "$text"
assert_line "second" 2 "$text"
assert_line "third" 3 "$text"

# ── Join / Split ─────────────────────────────────────────────────────────────

test_that "join combines with separator"
result=$(str_join "," "a" "b" "c")
assert_eq "a,b,c" "$result"

test_that "join with single item"
result=$(str_join "," "only")
assert_eq "only" "$result"

test_that "split_first returns before delimiter"
result=$(str_split_first "hello:world" ":")
assert_eq "hello" "$result"

test_that "split_last returns after delimiter"
result=$(str_split_last "hello:world" ":")
assert_eq "world" "$result"

# ── Regex match ──────────────────────────────────────────────────────────────

test_that "email-like pattern matches"
assert_match "[a-z]+@[a-z]+\\.[a-z]+" "user@example.com"

test_that "version pattern matches semver-like"
version="v1.2.3"
assert_match "^v[0-9]+\\.[0-9]+\\.[0-9]+$" "$version"

test_that "upper result matches all-caps pattern"
result=$(str_upper "hello")
assert_match "^[A-Z]+$" "$result"

# ── Multi-line output ─────────────────────────────────────────────────────────

test_that "words splits into lines"
result=$(str_words "hello world foo")
assert_line "hello" 1 "$result"
assert_line "world" 2 "$result"
assert_line "foo" 3 "$result"
assert_contains "$result" "world"
assert_not_contains "$result" "bar"

ptyunit_test_summary
