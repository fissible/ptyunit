#!/usr/bin/env bash
# mid-render-pause.sh — Scenario 2: partial output, 0.3s pause, then rest.
#
# Used by test_hostile.py to verify that the stability window resets when
# the second burst arrives (window-reset mechanism). The test uses
# stable_window=0.4 (> 0.3s pause) so the window does not fire mid-render.
printf 'first half'
sleep 0.3
printf ' second half\n'
