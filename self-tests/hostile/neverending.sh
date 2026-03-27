#!/usr/bin/env bash
# neverending.sh — Scenario 5: script that emits output continuously and never exits.
#
# Used by test_hostile.py to verify that the hard deadline (timeout) fires
# correctly when the stability window is never reached. PTYSession raises
# TimeoutError; pty_run.py returns exit code 124.
while true; do
    printf 'x'
    sleep 0.01
done
