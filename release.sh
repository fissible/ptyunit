#!/usr/bin/env bash
# release.sh — fissible standard release script
# Copy to the root of any fissible repo, or run directly.
# Usage: bash release.sh [patch|minor|major]
# Dependencies: git, git-cliff

set -e

# --- helpers ---

die()     { printf 'error: %s\n' "$1" >&2; exit 1; }
confirm() { printf '%s [y/N] ' "$1"; read -r ans; [[ "$ans" =~ ^[Yy]$ ]]; }

# --- preflight checks ---

[[ -f VERSION ]] || die "VERSION file not found — are you in a fissible repo root?"
[[ -f .cliff.toml ]] || die ".cliff.toml not found — copy it from fissible/.github"
command -v git-cliff >/dev/null 2>&1 || die "git-cliff not installed (brew install git-cliff)"
command -v git >/dev/null 2>&1 || die "git not found"

current_branch=$(git rev-parse --abbrev-ref HEAD)
[[ "$current_branch" == "main" ]] \
    || die "Releases must be cut from main (currently on: $current_branch)"

git diff --quiet && git diff --cached --quiet \
    || die "Working tree is dirty — commit or stash changes first"

# --- state ---

current=$(cat VERSION)
last_tag=$(git describe --tags --abbrev=0 2>/dev/null || printf '')

printf 'Current version : %s\n' "$current"
printf 'Last tag        : %s\n' "${last_tag:-none}"
printf '\n'

# --- show commits since last tag ---

if [[ -n "$last_tag" ]]; then
    printf 'Commits since %s:\n' "$last_tag"
    git log "${last_tag}..HEAD" --oneline --no-merges
else
    printf 'All commits (no previous tag):\n'
    git log --oneline --no-merges | head -20
fi
printf '\n'

# --- determine bump type ---

if [[ -n "$1" ]]; then
    bump="$1"
else
    # Suggest bump from conventional commit types
    recent=$(git log "${last_tag:+${last_tag}..}HEAD" --oneline --no-merges 2>/dev/null || git log --oneline --no-merges)
    has_breaking=0; has_feat=0
    while IFS= read -r line; do
        case "$line" in *'!:'*|*'BREAKING CHANGE'*) has_breaking=1 ;; esac
        case "$line" in *' feat'*|*'	feat'*) has_feat=1 ;; esac
    done <<EOF
$recent
EOF
    if [[ $has_breaking -eq 1 ]]; then suggested="major"
    elif [[ $has_feat -eq 1 ]];    then suggested="minor"
    else                                suggested="patch"
    fi
    printf 'Suggested bump: %s\n' "$suggested"
    printf 'Bump type [patch/minor/major, default: %s]: ' "$suggested"
    read -r bump
    bump="${bump:-$suggested}"
fi

case "$bump" in
    patch|minor|major) ;;
    *) die "Unknown bump type: '$bump' — use patch, minor, or major" ;;
esac

# --- calculate new version ---

IFS='.' read -r major minor patch <<< "$current"
case "$bump" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
esac

new_version="${major}.${minor}.${patch}"
new_tag="v${new_version}"

printf '\nNew version: %s → %s\n\n' "$current" "$new_version"
confirm "Proceed?" || { printf 'Aborted.\n'; exit 0; }

# --- update files ---

printf '%s\n' "$new_version" > VERSION
git-cliff --config .cliff.toml --tag "$new_tag" --output CHANGELOG.md

# --- commit and tag ---

git add VERSION CHANGELOG.md
git commit -m "chore: release ${new_tag}"
git tag -a "$new_tag" -m "$new_tag"

printf '\nTagged %s locally.\n' "$new_tag"

# --- push ---

if confirm "Push to origin?"; then
    git push && git push --tags
    printf '\nReleased %s\n' "$new_tag"
else
    printf 'Skipped push. When ready:\n  git push && git push --tags\n'
fi
