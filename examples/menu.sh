#!/usr/bin/env bash
# examples/menu.sh — Minimal arrow-key navigable menu (standalone, no dependencies)
#
# Renders the UI to /dev/tty.  Prints "You selected: <item>" or "No selection." to stdout.
# UP/DOWN arrows navigate; ENTER/SPACE select; q/Q/ESC quit without selection.
#
# Bash 3.2+ compatible.

set -u

ITEMS=("apple" "banana" "cherry" "date" "elderberry")
_n=${#ITEMS[@]}

# Open /dev/tty for TUI output (fixed fd 3 — bash 3.2 compatible)
exec 3>/dev/tty
_tui() { printf '%s' "$*" >&3; }

# ── Terminal raw mode ──────────────────────────────────────────────────────────
_saved_stty=""
_raw_enter() {
    _saved_stty=$(stty -g </dev/tty 2>/dev/null || printf '')
    stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null || true
}
_raw_exit() {
    [[ -n "$_saved_stty" ]] && stty "$_saved_stty" </dev/tty 2>/dev/null || true
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
_menu_cleanup() {
    _tui $'\033[?25h'   # show cursor
    _raw_exit
    exec 3>&- 2>/dev/null || true
}
trap '_menu_cleanup' EXIT

# ── State ─────────────────────────────────────────────────────────────────────
_selected=0

# ── Draw ──────────────────────────────────────────────────────────────────────
# Draws _n item lines + 1 footer line, then moves cursor back to the first item line.
_draw() {
    local i
    for (( i=0; i<_n; i++ )); do
        _tui $'\r\033[2K'
        if (( i == _selected )); then
            _tui $'\033[1m\033[32m> '"${ITEMS[$i]}"$'\033[0m'
        else
            _tui '  '"${ITEMS[$i]}"
        fi
        _tui $'\n'
    done
    _tui $'\r\033[2K'
    _tui $'\033[90m↑/↓ move  Enter select  q quit\033[0m'
    # Move cursor back to the first item line
    _tui $'\033['"$_n"'A'
}

# ── Run ───────────────────────────────────────────────────────────────────────
_tui $'\033[?25l'   # hide cursor
_raw_enter
_draw

_result=""
while true; do
    _key=""
    IFS= read -r -d '' -n1 _key </dev/tty 2>/dev/null || break
    case "$_key" in
        q|Q)
            break ;;
        $'\r'|$'\n'|' ')
            _result="${ITEMS[$_selected]}"; break ;;
        $'\x1b')
            _s1=""
            IFS= read -r -n1 -t 1 _s1 </dev/tty 2>/dev/null || true
            if [[ "$_s1" == "[" ]]; then
                _s2=""
                IFS= read -r -n1 -t 1 _s2 </dev/tty 2>/dev/null || true
                case "$_s2" in
                    A)  # UP
                        (( _selected > 0 )) && (( _selected-- )) || true
                        _draw ;;
                    B)  # DOWN
                        (( _selected < _n - 1 )) && (( _selected++ )) || true
                        _draw ;;
                esac
            else
                break   # bare ESC → quit
            fi ;;
    esac
done

# Move cursor past the menu block before printing result
_tui $'\033['"$(( _n + 1 ))"$'B\n'

if [[ -n "$_result" ]]; then
    printf 'You selected: %s\n' "$_result"
else
    printf 'No selection.\n'
fi
