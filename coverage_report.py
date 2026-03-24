#!/usr/bin/env python3
"""ptyunit/coverage_report.py — Parse bash xtrace output and generate coverage reports.

Reads a trace file produced by coverage.sh (PS4='+${BASH_SOURCE}:${LINENO} ')
and source files from --src to produce line-level coverage reports.

Usage:
    python3 coverage_report.py --trace <file> --src <dir> [--format text|json|html] [--min N]
"""

import argparse
import datetime
import fnmatch
import glob
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

# Matches bash function declaration lines — never executed by set -x, only definitions.
# Handles: name() {   name ()   function name {   function name() {
_FUNC_DEF_RE = re.compile(
    r'^function\s+[a-zA-Z_]\w*(\s*\(\))?\s*\{?\s*$'
    r'|^[a-zA-Z_]\w*\s*\(\)\s*\{?\s*$'
)

_BRANCH_RE = re.compile(
    r'\bif\b|\belif\b|\bwhile\b|\bfor\b|\buntil\b|\bcase\b|\|\||\&\&'
)

_BASH_KEYWORDS = frozenset({
    'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done',
    'case', 'esac', 'in', 'function', 'return', 'local', 'export',
    'declare', 'readonly', 'break', 'continue', 'exit', 'source',
    'select', 'until', 'shift', 'unset', 'set', 'true', 'false',
    'echo', 'printf', 'read', 'exec', 'eval',
})


def _ptyunit_version() -> str:
    try:
        return (Path(__file__).parent / 'VERSION').read_text().strip()
    except (IOError, OSError):
        return 'unknown'


def _pct_color(pct: float) -> str:
    """Return a CSS color string for a coverage percentage."""
    if pct >= 90:
        return '#4caf50'
    if pct >= 80:
        return '#8bc34a'
    if pct >= 60:
        return '#ff9800'
    return '#f44336'


def _highlight_bash(text: str) -> str:
    """Tokenize a bash source line and return syntax-highlighted HTML."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        # Comment: # to end of line
        if c == '#':
            out.append(f'<span class="hc">{_esc(text[i:])}</span>')
            break
        # Single-quoted string
        if c == "'":
            j = text.find("'", i + 1)
            j = j + 1 if j != -1 else n
            out.append(f'<span class="hs">{_esc(text[i:j])}</span>')
            i = j
            continue
        # Double-quoted string
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    j += 2
                elif text[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            out.append(f'<span class="hs">{_esc(text[i:j])}</span>')
            i = j
            continue
        # Backtick command substitution
        if c == '`':
            j = text.find('`', i + 1)
            j = j + 1 if j != -1 else n
            out.append(f'<span class="hv">{_esc(text[i:j])}</span>')
            i = j
            continue
        # Variable: $VAR  ${...}  $(...)
        if c == '$':
            j = i + 1
            if j < n:
                nc = text[j]
                if nc == '{':
                    depth, j = 1, j + 1
                    while j < n and depth:
                        if text[j] == '{':
                            depth += 1
                        elif text[j] == '}':
                            depth -= 1
                        j += 1
                elif nc == '(':
                    depth, j = 1, j + 1
                    while j < n and depth:
                        if text[j] == '(':
                            depth += 1
                        elif text[j] == ')':
                            depth -= 1
                        j += 1
                elif nc.isalpha() or nc == '_':
                    while j < n and (text[j].isalnum() or text[j] == '_'):
                        j += 1
                elif nc in '#?@*!-':
                    j += 1
                elif nc.isdigit():
                    j += 1
            out.append(f'<span class="hv">{_esc(text[i:j])}</span>')
            i = j
            continue
        # Word — keyword or plain identifier
        if c.isalpha() or c == '_':
            j = i
            while j < n and (text[j].isalnum() or text[j] in '_-'):
                j += 1
            word = text[i:j]
            if word in _BASH_KEYWORDS:
                out.append(f'<span class="hk">{_esc(word)}</span>')
            else:
                out.append(_esc(word))
            i = j
            continue
        out.append(_esc(c))
        i += 1
    return ''.join(out)


def _file_anchor(relative: str) -> str:
    """Sanitize a relative file path into a valid HTML id."""
    return re.sub(r'[^a-zA-Z0-9]', '-', relative)


def _esc(s: str) -> str:
    """HTML-escape a string."""
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')


# ── Source analysis ────────────────────────────────────────────────────────────

_TEST_DIRS = frozenset({'tests', 'test', 'self-tests', 'self_tests', 'spec', 'specs'})


def _load_coverageignore(src_dir: str) -> list:
    """Return glob patterns from .coverageignore in src_dir (or its parent)."""
    patterns = []
    for search in (src_dir, os.path.dirname(src_dir)):
        ignore_file = os.path.join(search, '.coverageignore')
        if os.path.isfile(ignore_file):
            with open(ignore_file) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        patterns.append(line)
            break
    return patterns


def _is_ignored(filepath: str, src_dir: str, patterns: list) -> bool:
    """Return True if filepath matches any .coverageignore pattern."""
    rel = os.path.relpath(filepath, src_dir)
    for pat in patterns:
        # Strip trailing slash — used to denote directories in .coverageignore
        pat = pat.rstrip('/')
        if fnmatch.fnmatch(rel, pat):
            return True
        # Also match files inside a directory pattern (e.g. "bench" matches "bench/foo.sh")
        if fnmatch.fnmatch(rel.split(os.sep)[0], pat):
            return True
    return False


def find_source_files(src_dir: str) -> list:
    """Find all .sh files under src_dir, skipping test directories, test files, and .coverageignore patterns."""
    ignore_patterns = _load_coverageignore(src_dir)
    files = []
    for root, dirs, names in os.walk(src_dir):
        dirs[:] = [d for d in dirs if d not in _TEST_DIRS]
        for name in names:
            if name.endswith('.sh') and not name.startswith('test-') and not name.endswith('-test.sh'):
                filepath = os.path.join(root, name)
                if not _is_ignored(filepath, src_dir, ignore_patterns):
                    files.append(filepath)
    return sorted(files)


def count_source_lines(filepath: str) -> dict:
    """Return {line_number: line_content} for executable lines."""
    executable = {}
    try:
        with open(filepath, 'r', errors='replace') as f:
            for i, line in enumerate(f, 1):
                stripped = line.strip()
                if not stripped:
                    continue
                if stripped.startswith('#'):
                    continue
                if stripped in ('{', '}', 'fi', 'do', 'done', 'then', 'else',
                                'elif', 'esac', ';;', ')', ';;)', '*)'):
                    continue
                if _FUNC_DEF_RE.match(stripped):
                    continue
                executable[i] = stripped
    except (IOError, OSError):
        pass
    return executable


# ── App detection ──────────────────────────────────────────────────────────────

def detect_app_info(src_dir: str) -> dict:
    """Detect application name and version from project metadata."""
    name = None
    version = None

    search_dirs = [src_dir]
    parent = os.path.dirname(os.path.realpath(src_dir))
    if parent and parent != os.path.realpath(src_dir):
        search_dirs.append(parent)

    for d in search_dirs:
        ver_file = os.path.join(d, 'VERSION')
        if os.path.isfile(ver_file):
            try:
                v = Path(ver_file).read_text().strip()
                if v:
                    version = version or v
                    break
            except (IOError, OSError):
                pass

    for d in search_dirs:
        pkg = os.path.join(d, 'package.json')
        if os.path.isfile(pkg):
            try:
                data = json.loads(Path(pkg).read_text())
                name = name or data.get('name')
                version = version or data.get('version')
            except (json.JSONDecodeError, IOError, OSError):
                pass

    if not name:
        try:
            result = subprocess.run(
                ['git', 'remote', 'get-url', 'origin'],
                capture_output=True, text=True, cwd=src_dir, timeout=3
            )
            if result.returncode == 0:
                m = re.search(r'[:/]([^/]+)/([^/]+?)(?:\.git)?$', result.stdout.strip())
                if m:
                    name = m.group(2)
        except Exception:
            pass

    if not name:
        name = os.path.basename(os.path.realpath(src_dir)) or 'project'

    return {'name': name, 'version': version}


# ── Language analysis ──────────────────────────────────────────────────────────

_LANG_COLORS = {
    '.sh':   ('#4ec94e', 'Shell'),
    '.bash': ('#89e051', 'Bash'),
    '.py':   ('#3572a5', 'Python'),
    '.rb':   ('#701516', 'Ruby'),
    '.js':   ('#f1e05a', 'JavaScript'),
    '.ts':   ('#2b7489', 'TypeScript'),
    '.go':   ('#00add8', 'Go'),
    '.rs':   ('#dea584', 'Rust'),
}
_LANG_DEFAULT_COLOR = '#666'


def detect_languages(results: list) -> list:
    """Tally executable line counts by file extension.

    Returns list of {lang, color, pct} sorted by pct descending.
    """
    totals = defaultdict(int)
    grand_total = 0
    for r in results:
        ext = os.path.splitext(r['relative'])[1].lower()
        totals[ext] += r['total']
        grand_total += r['total']
    if grand_total == 0:
        return []
    out = []
    for ext, count in sorted(totals.items(), key=lambda x: -x[1]):
        color, lang = _LANG_COLORS.get(
            ext, (_LANG_DEFAULT_COLOR, ext.lstrip('.').capitalize() or 'Other')
        )
        pct = round(count / grand_total * 100, 1)
        out.append({'lang': lang, 'color': color, 'pct': pct})
    return out


# ── Cyclomatic complexity ──────────────────────────────────────────────────────

def compute_complexity(filepath: str) -> int:
    """Estimate cyclomatic complexity for a bash file.

    Counts branching constructs: if, elif, while, for, until, case, &&, ||.
    Returns score >= 1 (baseline = 1).
    """
    score = 1
    try:
        with open(filepath, 'r', errors='replace') as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith('#'):
                    continue
                score += len(_BRANCH_RE.findall(stripped))
    except (IOError, OSError):
        pass
    return score


def _complexity_badge(score: int) -> str:
    """Return an HTML badge for a complexity score."""
    if score <= 5:
        label, cls = 'Low', 'cx-low'
    elif score <= 10:
        label, cls = 'Med', 'cx-med'
    elif score <= 20:
        label, cls = 'High', 'cx-high'
    else:
        label, cls = 'Crit', 'cx-crit'
    return f'<span class="cx {cls}" title="Cyclomatic complexity ≈ {score}">{label}</span>'


# ── Folder grouping ────────────────────────────────────────────────────────────

def group_by_folder(results: list) -> list:
    """Group file results by directory path, sorted alphabetically.

    Returns list of: {folder, files, hit, total, pct}
    Empty string folder = root-level files.
    """
    folders = defaultdict(list)
    for r in results:
        parts = r['relative'].split('/')
        folder = '/'.join(parts[:-1]) if len(parts) > 1 else ''
        folders[folder].append(r)

    out = []
    for folder in sorted(folders.keys()):
        files = folders[folder]
        hit = sum(f['hit'] for f in files)
        total = sum(f['total'] for f in files)
        pct = round(hit / total * 100, 1) if total else 0.0
        out.append({'folder': folder, 'files': files, 'hit': hit, 'total': total, 'pct': pct})
    return out


# ── Cross-run comparison ───────────────────────────────────────────────────────

def load_previous_stats(coverage_dir: str, current_ts: str):
    """Find and load the most recent JSON sidecar strictly before current_ts."""
    pattern = os.path.join(coverage_dir, '????_??_??_??_??_??.json')
    candidates = [
        f for f in glob.glob(pattern)
        if os.path.basename(f)[:-5] < current_ts
    ]
    if not candidates:
        return None
    try:
        return json.loads(Path(max(candidates)).read_text())
    except (IOError, OSError, json.JSONDecodeError):
        return None


def save_stats_json(coverage_dir: str, timestamp: str, results: list) -> None:
    """Write a JSON sidecar alongside the HTML report for future diff."""
    total_hit = sum(r['hit'] for r in results)
    total_total = sum(r['total'] for r in results)
    data = {
        'timestamp': timestamp,
        'total_hit': total_hit,
        'total_total': total_total,
        'total_pct': round(total_hit / total_total * 100, 1) if total_total else 0.0,
        'files': {
            r['relative']: {'hit': r['hit'], 'total': r['total'], 'pct': r['pct']}
            for r in results
        },
    }
    path = os.path.join(coverage_dir, f'{timestamp}.json')
    try:
        with open(path, 'w') as fh:
            json.dump(data, fh, indent=2)
    except (IOError, OSError):
        pass


def _delta_html(prev_pct: float, curr_pct: float, data_only: bool = False) -> str:
    """Return an HTML delta badge comparing prev and current coverage %."""
    delta = curr_pct - prev_pct
    if abs(delta) < 0.05:
        if data_only:
            return '0'
        return '<span class="d d-flat" title="No change from previous run" data-val="0">±0</span>'
    if delta > 0:
        if data_only:
            return f'{delta:.2f}'
        return f'<span class="d d-up" data-val="{delta:.2f}">▲ +{delta:.1f}%</span>'
    if data_only:
        return f'{delta:.2f}'
    return f'<span class="d d-dn" data-val="{delta:.2f}">▼ {delta:.1f}%</span>'


def _threshold_note(pct: float, delta=None) -> str:
    """Return a short interpretation of coverage quality."""
    if pct < 60:
        note = 'Below minimum threshold — significant coverage gaps'
    elif pct < 80:
        note = f'Below industry standard (80% baseline)'
    elif pct < 90:
        note = 'Meets baseline (80%)'
    else:
        note = 'Strong coverage (≥ 90%)'
    if delta is not None and delta < -5:
        note += f' · ⚠ Regression: {delta:+.1f}%'
    return note


# ── Trace parsing + coverage ───────────────────────────────────────────────────

def parse_trace(trace_path: str, src_dir: str) -> dict:
    """Parse xtrace output and return {absolute_filepath: {line_numbers_hit}}."""
    hits = defaultdict(set)
    pattern = re.compile(r'^\++(.+?):(\d+)\s')
    src_prefix = os.path.realpath(src_dir)

    try:
        with open(trace_path, 'r', errors='replace') as f:
            for line in f:
                m = pattern.match(line)
                if not m:
                    continue
                filepath = m.group(1)
                lineno = int(m.group(2))
                try:
                    abs_path = os.path.realpath(filepath)
                except (ValueError, OSError):
                    continue
                if abs_path.startswith(src_prefix):
                    hits[abs_path].add(lineno)
    except (IOError, OSError) as e:
        print(f'coverage: error reading trace: {e}', file=sys.stderr)

    return dict(hits)


def compute_coverage(src_dir: str, hits: dict) -> list:
    """Compute per-file coverage stats."""
    results = []
    for filepath in find_source_files(src_dir):
        abs_path = os.path.realpath(filepath)
        executable = count_source_lines(abs_path)
        total = len(executable)
        if total == 0:
            continue
        file_hits = hits.get(abs_path, set())
        hit = len(file_hits & set(executable.keys()))
        missed = total - hit
        pct = round((hit / total * 100) if total > 0 else 0, 1)
        missed_lines = sorted(set(executable.keys()) - file_hits)
        try:
            rel = os.path.relpath(abs_path, src_dir)
        except ValueError:
            rel = abs_path
        results.append({
            'file': abs_path,
            'relative': rel,
            'total': total,
            'hit': hit,
            'missed': missed,
            'pct': pct,
            'missed_lines': missed_lines,
        })
    return sorted(results, key=lambda r: r['relative'])


# ── Text / JSON formatters ─────────────────────────────────────────────────────

def format_text(results: list) -> str:
    """Plain text coverage report."""
    total_hit = sum(r['hit'] for r in results)
    total_total = sum(r['total'] for r in results)
    total_pct = (total_hit / total_total * 100) if total_total > 0 else 0
    lines = ['─' * 72,
             f'{"File":<45} {"Lines":>6} {"Hit":>6} {"Miss":>6} {"Cov":>6}',
             '─' * 72]
    for r in results:
        lines.append(f"{r['relative']:<45} {r['total']:>6} {r['hit']:>6} {r['missed']:>6} {r['pct']:>5.0f}%")
    lines += ['─' * 72,
              f"{'TOTAL':<45} {total_total:>6} {total_hit:>6} {total_total - total_hit:>6} {total_pct:>5.0f}%",
              '─' * 72]
    return '\n'.join(lines)


def format_json(results: list) -> str:
    """JSON coverage report."""
    total_hit = sum(r['hit'] for r in results)
    total_total = sum(r['total'] for r in results)
    return json.dumps({
        'total_lines': total_total,
        'total_hit': total_hit,
        'total_pct': round(total_hit / total_total * 100, 1) if total_total > 0 else 0,
        'files': [{
            'file': r['relative'], 'lines': r['total'], 'hit': r['hit'],
            'missed': r['missed'], 'pct': r['pct'], 'missed_lines': r['missed_lines'],
        } for r in results],
    }, indent=2)


# ── HTML formatter ─────────────────────────────────────────────────────────────

_CSS = '''
/* ── Reset ──────────────────────────────────────────────────── */
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}

/* ── Base ────────────────────────────────────────────────────── */
body{
  font-family:'Cascadia Code','SF Mono','Fira Code','Consolas',monospace;
  background:#161616;color:#c8c8c8;font-size:14px;line-height:1.5;
  padding-bottom:52px;
}

/* ── Report header ───────────────────────────────────────────── */
.rh{padding:18px 28px 14px;border-bottom:1px solid #222}
.app-name{font-size:1.35em;font-weight:700;color:#fff;letter-spacing:-0.01em}
.app-meta{color:#555;font-size:0.8em;margin-top:3px}

/* ── Total bar ───────────────────────────────────────────────── */
.total-bar{
  background:#1a1a1a;border-bottom:1px solid #222;
  padding:12px 28px;display:flex;align-items:baseline;
  flex-wrap:wrap;gap:8px 18px;
}
.total-pct{font-size:2.4em;font-weight:700;line-height:1}
.total-lines{color:#777;font-size:0.88em}
.total-delta{font-size:0.8em;font-weight:700;padding:2px 8px;border-radius:3px}
.total-delta.tup{background:#0d1f0d;color:#4caf50}
.total-delta.tdn{background:#1f0d0d;color:#f44336}
.total-note{flex-basis:100%;color:#555;font-size:0.76em;font-style:italic;padding-top:1px}

/* ── Main layout ─────────────────────────────────────────────── */
main{padding:0 28px 40px;max-width:1600px}
.sh{
  color:#666;font-size:0.72em;font-weight:700;
  text-transform:uppercase;letter-spacing:0.1em;
  padding:22px 0 6px;border-bottom:1px solid #1e1e1e;margin-bottom:2px;
}

/* ── Summary table ───────────────────────────────────────────── */
#ftbl{width:100%;border-collapse:collapse;margin:4px 0 36px}
#ftbl th{
  background:#1a1a1a;padding:7px 12px;text-align:left;
  border-bottom:2px solid #242424;color:#666;
  font-size:0.72em;font-weight:700;text-transform:uppercase;
  letter-spacing:0.07em;white-space:nowrap;user-select:none;
}
#ftbl th.s{cursor:pointer}
#ftbl th.s:hover{color:#aaa}
#ftbl th.sa .si::after{content:' ▲';color:#4e8cbf}
#ftbl th.sd .si::after{content:' ▼';color:#4e8cbf}
#ftbl td{
  padding:5px 12px;border-bottom:1px solid #1a1a1a;
  white-space:nowrap;vertical-align:middle;
}
#ftbl tr.fr:hover td{background:#1b1b1b}
.r{text-align:right!important;font-variant-numeric:tabular-nums}

/* ── Coverage mini-bar ───────────────────────────────────────── */
.bar{
  display:inline-flex;width:80px;height:8px;border-radius:3px;
  overflow:hidden;background:#242424;vertical-align:middle;margin-left:6px;
}
.bh{background:#3a8a3a}.bm{background:#8a3a3a}
.pv{font-weight:700}

/* ── Delta badges ────────────────────────────────────────────── */
.d{font-size:0.75em;font-weight:700;padding:1px 6px;border-radius:3px;white-space:nowrap}
.d-up{background:#0d1f0d;color:#66bb6a}
.d-dn{background:#1f0d0d;color:#ef5350}
.d-flat{color:#3a3a3a}

/* ── Complexity badges ───────────────────────────────────────── */
.cx{font-size:0.7em;font-weight:700;padding:1px 6px;border-radius:3px;
    white-space:nowrap;letter-spacing:0.02em}
.cx-low{background:#0d1f0d;color:#66bb6a}
.cx-med{background:#1f1f0d;color:#ffca28}
.cx-high{background:#1f150d;color:#ffa726}
.cx-crit{background:#1f0d0d;color:#ef5350}

/* ── File links ──────────────────────────────────────────────── */
a.fl{color:#4e8cbf;text-decoration:none}
a.fl:hover{text-decoration:underline}
.fdir{color:#555;font-size:0.85em}
.new-badge{font-size:0.7em;background:#0d1533;color:#4e8cbf;
           padding:1px 5px;border-radius:3px;margin-left:4px}

/* ── Folder groups (source section) ─────────────────────────── */
.fg{margin-bottom:2px}
.fg>summary,.fs>summary{
  list-style:none;display:flex;align-items:center;
  gap:10px;cursor:pointer;user-select:none;
}
.fg>summary::-webkit-details-marker,
.fs>summary::-webkit-details-marker{display:none}
.fg>summary{
  padding:7px 12px;background:#1a1a1a;
  border-top:1px solid #222;border-radius:2px 2px 0 0;
}
.fg>summary:hover{background:#1e1e1e}
.chv{
  font-size:0.58em;color:#444;flex-shrink:0;
  display:inline-block;transition:transform 0.13s ease;
}
.fg[open]>summary .chv,.fs[open]>summary .chv{transform:rotate(90deg)}
.flabel{color:#999;font-weight:700;flex:1;font-size:0.92em}
.fstats{color:#c8c8c8;font-size:0.8em}
.fpct{font-weight:700}

/* ── File sections (inside folder groups) ────────────────────── */
.fs{margin-bottom:1px}
.fs>summary{
  padding:5px 12px 5px 26px;
  border-bottom:1px solid #1a1a1a;
}
.fs>summary:hover{background:#1b1b1b}
.fs-name{color:#4e8cbf;flex:1;font-size:0.9em}
.fs-stats{color:#c8c8c8;font-size:0.78em}

/* ── Annotated source ────────────────────────────────────────── */
pre.src{margin:0;font-size:0.88em;overflow-x:auto;
        border-bottom:2px solid #1e1e1e;font-family:inherit;background:#111}
.sl{display:block;padding:0 12px 0 0;white-space:pre;line-height:1.45}
.sl:hover{background:#1b1b1b}
.sl-h{background:#0e2d18}.sl-m{background:#2d1010}
.ln{
  display:inline-block;width:3.5em;color:#3a3a3a;
  text-align:right;padding-right:10px;margin-right:10px;
  border-right:1px solid #272727;
  font-variant-numeric:tabular-nums;user-select:none;
}
.sl-h .ln{border-right-color:#1e5530;color:#3a6a4a}
.sl-m .ln{border-right-color:#5a1e1e;color:#7a4040}

/* ── Syntax highlighting ─────────────────────────────────────── */
.hk{color:#569cd6}
.hs{color:#ce9178}
.hc{color:#6a9955;font-style:italic}
.hv{color:#9cdcfe}

/* ── File dir in table ───────────────────────────────────────── */
.fdir{color:#666;font-size:0.9em}

/* ── Sticky footer ───────────────────────────────────────────── */
.foot{
  position:fixed;bottom:0;left:0;right:0;
  background:#111;border-top:1px solid #1e1e1e;
  padding:7px 28px;display:flex;align-items:center;
  gap:18px;font-size:0.76em;color:#444;z-index:200;
}
.foot a{color:#4e8cbf;text-decoration:none}
.foot a:hover{text-decoration:underline}
.fgrow{flex:1}
.fpath{color:#333;max-width:55%;overflow:hidden;
       text-overflow:ellipsis;white-space:nowrap}
'''

_JS = r'''
(function(){
  /* ── Sort summary table ── */
  var tbl=document.getElementById('ftbl');
  if(tbl){
    var col=-1,dir=1;
    tbl.querySelectorAll('th.s').forEach(function(th){
      th.insertAdjacentHTML('beforeend','<span class="si"></span>');
      th.addEventListener('click',function(){
        var c=parseInt(th.dataset.col,10);
        dir=(col===c)?-dir:1; col=c;
        tbl.querySelectorAll('th').forEach(function(t){t.classList.remove('sa','sd')});
        th.classList.add(dir>0?'sa':'sd');
        var tb=tbl.querySelector('tbody');
        var rows=Array.prototype.slice.call(tb.querySelectorAll('tr.fr'));
        rows.sort(function(a,b){
          var av=(a.cells[c]&&(a.cells[c].dataset.val||a.cells[c].textContent.trim()))||'';
          var bv=(b.cells[c]&&(b.cells[c].dataset.val||b.cells[c].textContent.trim()))||'';
          var an=parseFloat(av),bn=parseFloat(bv);
          return(isNaN(an)||isNaN(bn))?av.localeCompare(bv)*dir:(an-bn)*dir;
        });
        rows.forEach(function(r){tb.appendChild(r)});
      });
    });
  }

  /* ── Open details section on hash navigation ── */
  function openHash(){
    var id=window.location.hash.slice(1);
    if(!id)return;
    var el=document.getElementById(id);
    if(!el)return;
    var p=el;
    while(p){if(p.tagName==='DETAILS')p.open=true;p=p.parentElement}
    el.scrollIntoView({behavior:'smooth',block:'start'});
  }
  window.addEventListener('hashchange',openHash);
  openHash();
})();
'''

_INDEX_JS = r'''
(function(){
  var links=document.querySelectorAll('nav a');
  var iframe=document.querySelector('iframe[name="report"]');
  function mark(href){
    links.forEach(function(a){a.classList.toggle('active',a.getAttribute('href')===href)});
  }
  if(iframe)mark(iframe.getAttribute('src'));
  links.forEach(function(a){
    a.addEventListener('click',function(){mark(a.getAttribute('href'))});
  });
})();
'''


def format_html(
    results: list,
    src_dir: str,
    prev_stats=None,
    app_info=None,
    script_path: str = None,
    generated_dt: datetime.datetime = None,
) -> str:
    """HTML coverage report with folder hierarchy, comparison deltas, and sorting."""

    total_hit = sum(r['hit'] for r in results)
    total_total = sum(r['total'] for r in results)
    total_pct = round((total_hit / total_total * 100) if total_total > 0 else 0, 1)

    version = _ptyunit_version()
    app_name = (app_info or {}).get('name') or 'Coverage Report'
    app_ver = (app_info or {}).get('version')
    dt = generated_dt or datetime.datetime.now()
    dt_str = _format_display_date(dt)
    dt_iso = dt.strftime('%Y-%m-%dT%H:%M:%S')

    # ── Total bar: compute delta and tint ────────────────────────────────────
    prev_total_pct = (prev_stats or {}).get('total_pct')
    if prev_total_pct is not None:
        total_delta = total_pct - prev_total_pct
        if total_delta > 0.05:
            delta_html = (f'<span class="total-delta tup">▲ +{total_delta:.1f}%</span>')
        elif total_delta < -0.05:
            delta_html = (f'<span class="total-delta tdn">▼ {total_delta:.1f}%</span>')
        else:
            delta_html = ''
        note = _threshold_note(total_pct, total_delta)
    else:
        delta_html = ''
        note = _threshold_note(total_pct)

    # ── App meta line ────────────────────────────────────────────────────────
    meta_parts = []
    if app_ver:
        meta_parts.append(f'v{app_ver}')
    # Skip "ptyunit vX" attribution when measuring ptyunit itself (redundant)
    if app_name != 'ptyunit':
        meta_parts.append(f'ptyunit v{version}')
    meta_parts.append(f'<time datetime="{dt_iso}">{dt_str}</time>')
    app_meta = ' · '.join(meta_parts)

    # ── Build summary table rows (flat, sortable) ────────────────────────────
    prev_files = (prev_stats or {}).get('files', {})
    tbody_rows = []
    for r in results:
        anchor = _file_anchor(r['relative'])
        parts = r['relative'].split('/')
        fname = parts[-1]
        fdir = ('/'.join(parts[:-1]) + '/') if len(parts) > 1 else ''

        # Coverage bar
        hit_w = max(0, min(80, int(r['pct'] * 0.8)))
        miss_w = 80 - hit_w
        bar = (f'<span class="bar"><span class="bh" style="width:{hit_w}px"></span>'
               f'<span class="bm" style="width:{miss_w}px"></span></span>')

        # Complexity
        cx_score = compute_complexity(r['file'])
        cx_badge = _complexity_badge(cx_score)

        # Delta vs previous report
        prev_file = prev_files.get(r['relative'])
        if prev_file is not None:
            delta_cell = _delta_html(prev_file['pct'], r['pct'])
            delta_val = _delta_html(prev_file['pct'], r['pct'], data_only=True)
        elif prev_stats is not None:
            # File is new this run
            delta_cell = '<span class="new-badge">new</span>'
            delta_val = '0'
        else:
            # No previous run to compare against — leave cell empty
            delta_cell = ''
            delta_val = '0'

        tbody_rows.append(
            f'<tr class="fr">'
            f'<td data-val="{_esc(r["relative"])}">'
            f'{"<span class=fdir>" + _esc(fdir) + "</span>" if fdir else ""}'
            f'<a href="#{anchor}" class="fl">{_esc(fname)}</a>'
            f'</td>'
            f'<td class="r" data-val="{r["total"]}">{r["total"]}</td>'
            f'<td class="r" data-val="{r["hit"]}">{r["hit"]}</td>'
            f'<td class="r" data-val="{r["missed"]}">{r["missed"]}</td>'
            f'<td class="r" data-val="{r["pct"]}">'
            f'<span class="pv">{r["pct"]:.0f}%</span>{bar}'
            f'</td>'
            f'<td class="r" data-val="{cx_score}">{cx_badge}</td>'
            f'<td class="r" data-val="{delta_val}">{delta_cell}</td>'
            f'</tr>'
        )

    # ── Build source section (folder hierarchy) ──────────────────────────────
    source_sections = []
    for grp in group_by_folder(results):
        folder = grp['folder']
        folder_label = (folder + '/') if folder else '(root)'
        anchor_folder = _file_anchor(folder) if folder else 'root'

        # Per-folder delta
        folder_delta = ''
        if prev_stats is not None:
            # Compute folder prev pct from individual file deltas
            prev_f_hits = sum(
                prev_files.get(f['relative'], {}).get('hit', 0) for f in grp['files']
            )
            prev_f_total = sum(
                prev_files.get(f['relative'], {}).get('total', 0) for f in grp['files']
            )
            if prev_f_total > 0:
                prev_f_pct = round(prev_f_hits / prev_f_total * 100, 1)
                folder_delta = ' ' + _delta_html(prev_f_pct, grp['pct'])

        source_sections.append(
            f'<details class="fg" id="folder-{anchor_folder}" open>'
            f'<summary>'
            f'<span class="chv">▶</span>'
            f'<span class="flabel">{_esc(folder_label)}</span>'
            f'<span class="fstats">'
            f'{len(grp["files"])} file{"s" if len(grp["files"]) != 1 else ""}'
            f' · <span class="fpct" style="color:{_pct_color(grp["pct"])}">{grp["pct"]:.0f}%</span>'
            f'{folder_delta}'
            f'</span>'
            f'</summary>'
        )

        for r in grp['files']:
            anchor = _file_anchor(r['relative'])
            fname = r['relative'].split('/')[-1]
            missed_set = set(r['missed_lines'])
            executable = count_source_lines(r['file'])

            prev_file = prev_files.get(r['relative'])
            file_delta = ''
            if prev_file is not None:
                file_delta = ' ' + _delta_html(prev_file['pct'], r['pct'])
            elif prev_stats is not None:
                file_delta = ' <span class="new-badge">new</span>'

            line_spans = []
            try:
                with open(r['file'], 'r', errors='replace') as fh:
                    for i, line in enumerate(fh, 1):
                        highlighted = _highlight_bash(line.rstrip())
                        if i in executable:
                            cls = 'sl-m' if i in missed_set else 'sl-h'
                            line_spans.append(
                                f'<span class="sl {cls}"><span class="ln">{i}</span>{highlighted}</span>'
                            )
                        else:
                            line_spans.append(
                                f'<span class="sl"><span class="ln">{i}</span>{highlighted}</span>'
                            )
            except (IOError, OSError):
                line_spans.append('<span class="sl">(could not read source)</span>')

            # Join spans with no separator — newlines inside <pre> render as blank lines
            source_sections.append(
                f'<details class="fs" id="{anchor}">'
                f'<summary>'
                f'<span class="chv">▶</span>'
                f'<span class="fs-name">{_esc(fname)}</span>'
                f'<span class="fs-stats">'
                f'{r["hit"]}/{r["total"]} · <span style="color:{_pct_color(r["pct"])};font-weight:700">{r["pct"]:.0f}%</span>'
                f'{file_delta}'
                f'</span>'
                f'</summary>'
                f'<pre class="src"><code>{"".join(line_spans)}</code></pre>'
                f'</details>'
            )
        source_sections.append('</details>')

    # ── Footer path ──────────────────────────────────────────────────────────
    footer_path = _esc(script_path or str(Path(__file__).resolve().parent))

    # ── Assemble HTML ────────────────────────────────────────────────────────
    parts = [
        f'<!DOCTYPE html>',
        f'<html lang="en">',
        f'<head>',
        f'<meta charset="utf-8">',
        f'<meta name="viewport" content="width=device-width,initial-scale=1">',
        f'<title>{_esc(app_name)} coverage</title>',
        f'<style>{_CSS}</style>',
        f'</head>',
        f'<body id="top">',

        # Header
        f'<header class="rh">',
        f'<div class="app-name">{_esc(app_name)}</div>',
        f'<div class="app-meta">{app_meta}</div>',
        f'</header>',

        # Total bar
        f'<div class="total-bar">',
        f'<span class="total-pct" style="color:{_pct_color(total_pct)}">{total_pct:.0f}%</span>',
        f'<span class="total-lines">{total_hit:,} / {total_total:,} lines covered</span>',
        delta_html,
        f'<span class="total-note">{_esc(note)}</span>',
        f'</div>',

        # Main content
        f'<main>',

        # Summary table
        f'<p class="sh">Files</p>',
        f'<table id="ftbl">',
        f'<thead><tr>',
        f'<th class="s" data-col="0">File</th>',
        f'<th class="s r" data-col="1">Lines</th>',
        f'<th class="s r" data-col="2">Hit</th>',
        f'<th class="s r" data-col="3">Miss</th>',
        f'<th class="s r" data-col="4">Coverage</th>',
        f'<th class="s r" data-col="5">Complexity</th>',
        f'<th class="s r" data-col="6">Δ vs prev</th>',
        f'</tr></thead>',
        f'<tbody>',
        '\n'.join(tbody_rows),
        f'</tbody>',
        f'</table>',

        # Source hierarchy
        f'<p class="sh">Source</p>',
        '\n'.join(source_sections),

        f'</main>',

        # Sticky footer
        f'<footer class="foot">',
        f'<a href="#top">↑ top</a>',
        f'<span>Generated <time datetime="{dt_iso}">{dt_str}</time></span>',
        f'<span class="fgrow"></span>',
        f'<span class="fpath" title="{footer_path}">{footer_path}</span>',
        f'</footer>',

        f'<script>{_JS}</script>',
        f'</body>',
        f'</html>',
    ]

    return '\n'.join(parts)


# ── Index regeneration ─────────────────────────────────────────────────────────

def _parse_report_dt(filename: str):
    """Parse YYYY_MM_DD_HH_MM_SS from a report filename, return datetime or None."""
    stem = filename[:-5] if filename.endswith('.html') else filename
    try:
        return datetime.datetime.strptime(stem, '%Y_%m_%d_%H_%M_%S')
    except ValueError:
        return None


def _format_display_date(dt: datetime.datetime) -> str:
    """Format as 'Month D, YYYY, H:MM am/pm' (12-hour, nav sort uses filenames)."""
    hour = int(dt.strftime('%I'))
    minute = dt.strftime('%M')
    ampm = dt.strftime('%p').lower()
    return f'{dt.strftime("%B")} {dt.day}, {dt.year}, {hour}:{minute} {ampm}'


def regenerate_index(coverage_dir: str) -> None:
    """Rewrite coverage/index.html as a nav bar + iframe with active-link tracking."""
    pattern = os.path.join(coverage_dir, '????_??_??_??_??_??.html')
    entries = []
    for filepath in sorted(glob.glob(pattern)):
        name = os.path.basename(filepath)
        dt = _parse_report_dt(name)
        if dt is not None:
            entries.append((name, _format_display_date(dt)))

    if not entries:
        return

    latest = entries[-1][0]
    links = '\n  '.join(
        f'<a href="{name}" target="report">{label}</a>'
        for name, label in entries
    )

    html = f'''<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>ptyunit coverage</title>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:'Cascadia Code','SF Mono','Fira Code',monospace;
     background:#111;color:#c8c8c8;display:flex;flex-direction:column;height:100vh}}
nav{{background:#161616;border-bottom:1px solid #1e1e1e;padding:8px 14px;
     overflow-x:auto;white-space:nowrap;flex-shrink:0}}
nav a{{
  display:inline-block;color:#4e8cbf;text-decoration:none;
  padding:4px 10px;margin-right:4px;border-radius:3px;
  border:1px solid #242424;font-size:12px;font-family:inherit;
  transition:background 0.1s,border-color 0.1s;
}}
nav a:hover{{background:#1e1e1e;color:#7aacdf}}
nav a.active{{background:#1e2a38;border-color:#4e8cbf;color:#7aacdf}}
iframe{{flex:1;border:none;width:100%}}
</style>
</head><body>
<nav>
  {links}
</nav>
<iframe name="report" src="{latest}"></iframe>
<script>{_INDEX_JS}</script>
</body></html>'''

    with open(os.path.join(coverage_dir, 'index.html'), 'w') as f:
        f.write(html)


# ── Entry point ────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='ptyunit coverage report')
    parser.add_argument('--trace', required=True, help='Path to xtrace output file')
    parser.add_argument('--src', required=True, help='Source directory to measure')
    parser.add_argument('--format', default='text', choices=['text', 'json', 'html'])
    parser.add_argument('--min', type=float, default=0,
                        help='Minimum coverage %% (exit 1 if below)')
    args = parser.parse_args()

    hits = parse_trace(args.trace, args.src)
    results = compute_coverage(args.src, hits)

    if args.format == 'text':
        print(format_text(results))
    elif args.format == 'json':
        print(format_json(results))
    elif args.format == 'html':
        os.makedirs('coverage', exist_ok=True)
        now = datetime.datetime.now()
        timestamp = now.strftime('%Y_%m_%d_%H_%M_%S')
        report_name = f'{timestamp}.html'
        report_path = os.path.join('coverage', report_name)

        prev_stats = load_previous_stats('coverage', timestamp)
        app_info = detect_app_info(args.src)
        script_path = str(Path(__file__).resolve().parent)

        html = format_html(
            results, args.src,
            prev_stats=prev_stats,
            app_info=app_info,
            script_path=script_path,
            generated_dt=now,
        )
        with open(report_path, 'w') as f:
            f.write(html)

        save_stats_json('coverage', timestamp, results)
        print(f'HTML coverage report written to {report_path}')
        regenerate_index('coverage')
        print(format_text(results))

    total_hit = sum(r['hit'] for r in results)
    total_total = sum(r['total'] for r in results)
    total_pct = (total_hit / total_total * 100) if total_total > 0 else 0

    if args.min > 0 and total_pct < args.min:
        print(f'\nFAIL: coverage {total_pct:.0f}% is below minimum {args.min:.0f}%',
              file=sys.stderr)
        return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
