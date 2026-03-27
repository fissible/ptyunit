#!/usr/bin/env bash
# cpu-work.sh — Scenario 4: CPU-bound computation before producing output.
#
# Used by test_hostile.py under cpulimit -l 10 to verify that wait_for_stable()
# correctly waits for first output from a throttled process (first-byte gate).
# All computation is in bash arithmetic to ensure cpulimit throttles it.
_result=0
_i=0
while [[ $_i -le 50000 ]]; do
    _result=$(( _result + _i ))
    _i=$(( _i + 1 ))
done
printf 'computed: %s\n' "$_result"
