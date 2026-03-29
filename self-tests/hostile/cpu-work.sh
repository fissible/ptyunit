#!/usr/bin/env bash
# cpu-work.sh — Scenario 4: CPU-bound computation before producing output.
#
# Used by test_hostile.py to verify that wait_for_stable() correctly waits
# for first output from a slow process (first-byte gate).  The loop is large
# enough to take several seconds on a typical CI runner before emitting output.
# All computation is in bash arithmetic (intentionally slow).
_result=0
_i=0
while [[ $_i -le 500000 ]]; do
    _result=$(( _result + _i ))
    _i=$(( _i + 1 ))
done
printf 'computed: %s\n' "$_result"
