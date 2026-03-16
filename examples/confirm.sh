#!/usr/bin/env bash
# examples/confirm.sh — Minimal yes/no confirm prompt (standalone, no dependencies)
#
# Renders the UI to /dev/tty.  Prints "Confirmed" or "Cancelled" to stdout on exit.
# Accepts: y/Y → Confirmed; n/N/q/Q/ESC → Cancelled; LEFT/RIGHT arrows navigate;
# ENTER/SPACE confirm the highlighted choice.
#
# Bash 3.2+ compatible.

set -u

# Open /dev/tty for TUI output (fixed fd 3 — bash 3.2 compatible, no {varname} alloc)
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
_confirm_cleanup() {
    _tui $'\033[?25h'   # show cursor
    _raw_exit
    exec 3>&- 2>/dev/null || true
}
trap '_confirm_cleanup' EXIT

# ── State ─────────────────────────────────────────────────────────────────────
_selected=0   # 0=Yes  1=No

# ── Draw ──────────────────────────────────────────────────────────────────────
_draw() {
    _tui $'\r\033[2K'
    _tui 'Confirm? '
    if (( _selected == 0 )); then
        _tui $'\033[7m[ Yes ]\033[0m   No  '
    else
        _tui '  Yes    \033[7m[ No  ]\033[0m'
    fi
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
        y|Y)
            _result="Confirmed"; break ;;
        n|N|q|Q)
            _result="Cancelled"; break ;;
        $'\r'|$'\n'|' ')
            if (( _selected == 0 )); then _result="Confirmed"
            else                          _result="Cancelled"
            fi
            break ;;
        $'\x1b')
            _s1=""
            IFS= read -r -n1 -t 1 _s1 </dev/tty 2>/dev/null || true
            if [[ "$_s1" == "[" ]]; then
                _s2=""
                IFS= read -r -n1 -t 1 _s2 </dev/tty 2>/dev/null || true
                case "$_s2" in
                    C) _selected=1; _draw ;;    # RIGHT → No
                    D) _selected=0; _draw ;;    # LEFT  → Yes
                esac
            else
                _result="Cancelled"; break      # bare ESC → cancel
            fi ;;
    esac
done

_tui $'\n'
printf '%s\n' "${_result:-Cancelled}"
