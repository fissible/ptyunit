#!/usr/bin/env bash
# mathlib.sh — Integer math utilities
# Exercises: assert_eq, assert_output, assert_gt/lt/ge/le, assert_true/false

math_add()      { printf '%d' "$(( $1 + $2 ))"; }
math_sub()      { printf '%d' "$(( $1 - $2 ))"; }
math_mul()      { printf '%d' "$(( $1 * $2 ))"; }
math_div()      { (( $2 == 0 )) && { printf 'error: division by zero' >&2; return 1; }; printf '%d' "$(( $1 / $2 ))"; }
math_mod()      { (( $2 == 0 )) && { printf 'error: division by zero' >&2; return 1; }; printf '%d' "$(( $1 % $2 ))"; }
math_abs()      { local n="$1"; (( n < 0 )) && n=$(( -n )); printf '%d' "$n"; }
math_max()      { (( $1 >= $2 )) && printf '%d' "$1" || printf '%d' "$2"; }
math_min()      { (( $1 <= $2 )) && printf '%d' "$1" || printf '%d' "$2"; }
math_clamp()    { local val="$1" lo="$2" hi="$3"; (( val < lo )) && val=$lo; (( val > hi )) && val=$hi; printf '%d' "$val"; }
math_is_even()  { (( $1 % 2 == 0 )); }
math_is_positive() { (( $1 > 0 )); }
math_factorial() {
    local n="$1" result=1
    (( n < 0 )) && { printf 'error: negative factorial' >&2; return 1; }
    local i
    for (( i=2; i<=n; i++ )); do
        (( result *= i ))
    done
    printf '%d' "$result"
}
math_fibonacci() {
    local n="$1" a=0 b=1
    (( n < 0 )) && { printf 'error: negative index' >&2; return 1; }
    (( n == 0 )) && { printf '0'; return; }
    local i tmp
    for (( i=2; i<=n; i++ )); do
        tmp=$b
        (( b = a + b ))
        a=$tmp
    done
    printf '%d' "$b"
}
