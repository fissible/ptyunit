#!/usr/bin/env bash
# slow-start.sh — Scenario 1: no output for 1.5s, then a single line.
#
# Used by test_hostile.py to verify that wait_for_stable() does not declare
# the screen stable during the silence (first-byte gate must hold).
sleep 1.5
printf 'slow start output\n'
