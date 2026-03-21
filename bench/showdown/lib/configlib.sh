#!/usr/bin/env bash
# configlib.sh — INI-style config parser
# Exercises: assert_eq, assert_contains, assert_line, assert_match, assert_not_null,
#            assert_file_exists, setup/teardown, skip

# Parse a key=value config file. Supports:
#   - Comments (lines starting with # or ;)
#   - Sections ([section])
#   - Key=value pairs (whitespace around = is trimmed)
#   - Empty lines are ignored

config_get() {
    local file="$1" section="$2" key="$3"
    local in_section=0 current_section=""
    [[ -f "$file" ]] || return 1
    while IFS= read -r line; do
        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        # Skip empty lines and comments
        [[ -z "$line" || "$line" == \#* || "$line" == \;* ]] && continue
        # Section header
        if [[ "$line" == \[*\] ]]; then
            current_section="${line#[}"
            current_section="${current_section%]}"
            if [[ "$current_section" == "$section" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi
        # Key=value
        if (( in_section )); then
            local k="${line%%=*}"
            local v="${line#*=}"
            # Trim whitespace
            k="${k%"${k##*[![:space:]]}"}"
            v="${v#"${v%%[![:space:]]*}"}"
            if [[ "$k" == "$key" ]]; then
                printf '%s' "$v"
                return 0
            fi
        fi
    done < "$file"
    return 1
}

config_sections() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        if [[ "$line" == \[*\] ]]; then
            local s="${line#[}"
            s="${s%]}"
            printf '%s\n' "$s"
        fi
    done < "$file"
}

config_keys() {
    local file="$1" section="$2"
    local in_section=0
    [[ -f "$file" ]] || return 1
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* || "$line" == \;* ]] && continue
        if [[ "$line" == \[*\] ]]; then
            local current="${line#[}"
            current="${current%]}"
            [[ "$current" == "$section" ]] && in_section=1 || in_section=0
            continue
        fi
        if (( in_section )) && [[ "$line" == *=* ]]; then
            local k="${line%%=*}"
            k="${k%"${k##*[![:space:]]}"}"
            printf '%s\n' "$k"
        fi
    done < "$file"
}

config_has_section() {
    local file="$1" section="$2"
    [[ -f "$file" ]] || return 1
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ "$line" == "[$section]" ]] && return 0
    done < "$file"
    return 1
}

config_has_key() {
    local file="$1" section="$2" key="$3"
    config_get "$file" "$section" "$key" > /dev/null 2>&1
}

config_validate() {
    local file="$1"
    [[ -f "$file" ]] || { printf 'file not found: %s' "$file"; return 1; }
    local line_num=0 has_error=0
    while IFS= read -r line; do
        (( line_num++ ))
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* || "$line" == \;* ]] && continue
        [[ "$line" == \[*\] ]] && continue
        if [[ "$line" != *=* ]]; then
            printf 'syntax error at line %d: %s\n' "$line_num" "$line"
            has_error=1
        fi
    done < "$file"
    return $has_error
}
