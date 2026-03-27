#!/usr/bin/env bash
# jittery.sh — Scenario 3: 500 bytes emitted one at a time with ~1ms between each.
#
# Used by test_hostile.py to verify that the stability window only fires after
# the full burst ends, not during it. Each byte resets the window.
for _i in $(seq 1 500); do
    printf 'x'
    sleep 0.001
done
printf '\n'
