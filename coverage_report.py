#!/usr/bin/env python3
"""ptyunit/coverage_report.py — Parse bash xtrace output and generate coverage reports.

Reads a trace file produced by coverage.sh (PS4='+${BASH_SOURCE}:${LINENO} ')
and source files from --src to produce line-level coverage reports.

Usage:
    python3 coverage_report.py --trace <file> --src <dir> [--format text|json|html] [--min N]
"""

import argparse
import datetime
import glob
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

# Matches bash function declaration lines — never executed by set -x, only definitions.
# Handles: name() {   name ()   function name {   function name() {
_FUNC_DEF_RE = re.compile(
    r'^function\s+[a-zA-Z_]\w*(\s*\(\))?\s*\{?\s*$'
    r'|^[a-zA-Z_]\w*\s*\(\)\s*\{?\s*$'
)


def _ptyunit_version() -> str:
    try:
        return (Path(__file__).parent / 'VERSION').read_text().strip()
    except (IOError, OSError):
        return 'unknown'


def _file_anchor(relative: str) -> str:
    """Sanitize a relative file path into a valid HTML id."""
    return re.sub(r'[^a-zA-Z0-9]', '-', relative)


def find_source_files(src_dir: str) -> list[str]:
    """Find all .sh files under src_dir."""
    files = []
    for root, _, names in os.walk(src_dir):
        for name in names:
            if name.endswith('.sh'):
                files.append(os.path.join(root, name))
    return sorted(files)


def count_source_lines(filepath: str) -> dict[int, str]:
    """Return a dict of line_number → line_content for executable lines.

    Skips blank lines, comments, and lines that are only whitespace/braces.
    """
    executable = {}
    try:
        with open(filepath, 'r', errors='replace') as f:
            for i, line in enumerate(f, 1):
                stripped = line.strip()
                # Skip empty, comments, pure structural lines
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


def parse_trace(trace_path: str, src_dir: str) -> dict[str, set[int]]:
    """Parse the xtrace output and return hits per file.

    Returns: {absolute_filepath: {line_numbers_hit}}
    """
    hits = defaultdict(set)
    # Match: +/path/to/file.sh:42 ...
    # Also handles: ++/path (nested subshells add extra +)
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

                # Resolve to absolute and check if it's under src_dir
                try:
                    abs_path = os.path.realpath(filepath)
                except (ValueError, OSError):
                    continue

                if abs_path.startswith(src_prefix):
                    hits[abs_path].add(lineno)
    except (IOError, OSError) as e:
        print(f"coverage: error reading trace: {e}", file=sys.stderr)

    return dict(hits)


def compute_coverage(src_dir: str, hits: dict[str, set[int]]) -> list[dict]:
    """Compute per-file coverage stats.

    Returns list of dicts with keys: file, relative, total, hit, missed, pct, missed_lines
    """
    source_files = find_source_files(src_dir)
    results = []

    for filepath in source_files:
        abs_path = os.path.realpath(filepath)
        executable = count_source_lines(abs_path)
        total = len(executable)
        if total == 0:
            continue

        file_hits = hits.get(abs_path, set())
        hit = len(file_hits & set(executable.keys()))
        missed = total - hit
        pct = (hit / total * 100) if total > 0 else 0

        missed_lines = sorted(set(executable.keys()) - file_hits)

        # Relative path for display
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
            'pct': round(pct, 1),
            'missed_lines': missed_lines,
        })

    return sorted(results, key=lambda r: r['relative'])


def format_text(results: list[dict]) -> str:
    """Plain text coverage report."""
    lines = []
    total_hit = sum(r['hit'] for r in results)
    total_total = sum(r['total'] for r in results)
    total_pct = (total_hit / total_total * 100) if total_total > 0 else 0

    lines.append('─' * 72)
    lines.append(f'{"File":<45} {"Lines":>6} {"Hit":>6} {"Miss":>6} {"Cov":>6}')
    lines.append('─' * 72)

    for r in results:
        pct_str = f"{r['pct']:.0f}%"
        lines.append(f"{r['relative']:<45} {r['total']:>6} {r['hit']:>6} {r['missed']:>6} {pct_str:>6}")

    lines.append('─' * 72)
    total_pct_str = f"{total_pct:.0f}%"
    lines.append(f"{'TOTAL':<45} {total_total:>6} {total_hit:>6} {total_total - total_hit:>6} {total_pct_str:>6}")
    lines.append('─' * 72)

    return '\n'.join(lines)


def format_json(results: list[dict]) -> str:
    """JSON coverage report."""
    total_hit = sum(r['hit'] for r in results)
    total_total = sum(r['total'] for r in results)
    return json.dumps({
        'total_lines': total_total,
        'total_hit': total_hit,
        'total_pct': round(total_hit / total_total * 100, 1) if total_total > 0 else 0,
        'files': [{
            'file': r['relative'],
            'lines': r['total'],
            'hit': r['hit'],
            'missed': r['missed'],
            'pct': r['pct'],
            'missed_lines': r['missed_lines'],
        } for r in results],
    }, indent=2)


def format_html(results: list[dict], src_dir: str) -> str:
    """HTML coverage report with per-file detail."""
    total_hit = sum(r['hit'] for r in results)
    total_total = sum(r['total'] for r in results)
    total_pct = (total_hit / total_total * 100) if total_total > 0 else 0

    version = _ptyunit_version()
    html = ['<!DOCTYPE html><html><head>',
            '<meta charset="utf-8">',
            '<title>ptyunit coverage</title>',
            '<style>',
            'body { font-family: monospace; background: #1a1a1a; color: #e0e0e0; margin: 2em; }',
            'table { border-collapse: collapse; width: 100%; }',
            'th, td { padding: 4px 12px; text-align: left; border-bottom: 1px solid #333; }',
            'th { background: #2a2a2a; }',
            '.hit { background: #1a3a1a; }',
            '.miss { background: #3a1a1a; }',
            '.pct { text-align: right; }',
            '.num { text-align: right; }',
            '.bar { display: inline-block; height: 12px; }',
            '.bar-hit { background: #4a8; }',
            '.bar-miss { background: #a44; }',
            'h1 { color: #fff; }',
            'h2 { color: #aaa; margin-top: 2em; }',
            '.summary { font-size: 1.2em; margin-bottom: 1em; }',
            '.meta { color: #888; font-size: 0.9em; margin-bottom: 1.5em; }',
            'a { color: #7af; text-decoration: none; }',
            'a:hover { text-decoration: underline; }',
            '</style></head><body>',
            f'<h1>ptyunit coverage</h1>',
            f'<p class="meta">ptyunit v{version}</p>',
            f'<p class="summary">Total: {total_hit}/{total_total} lines ({total_pct:.0f}%)</p>',
            '<table><tr><th>File</th><th class="num">Lines</th><th class="num">Hit</th>',
            '<th class="num">Miss</th><th class="pct">Coverage</th><th>Bar</th></tr>']

    for r in results:
        bar_w = 100
        hit_w = int(r['pct'])
        miss_w = bar_w - hit_w
        bar = (f'<span class="bar bar-hit" style="width:{hit_w}px"></span>'
               f'<span class="bar bar-miss" style="width:{miss_w}px"></span>')
        anchor = _file_anchor(r['relative'])
        html.append(f'<tr><td><a href="#{anchor}">{r["relative"]}</a></td>'
                    f'<td class="num">{r["total"]}</td>'
                    f'<td class="num">{r["hit"]}</td>'
                    f'<td class="num">{r["missed"]}</td>'
                    f'<td class="pct">{r["pct"]:.0f}%</td>'
                    f'<td>{bar}</td></tr>')

    html.append('</table>')

    # Per-file source view with hit/miss highlighting
    for r in results:
        missed_set = set(r['missed_lines'])
        executable = count_source_lines(r['file'])
        anchor = _file_anchor(r['relative'])
        html.append(f'<h2 id="{anchor}">{r["relative"]} ({r["pct"]:.0f}%)</h2>')
        html.append('<pre>')
        try:
            with open(r['file'], 'r', errors='replace') as f:
                for i, line in enumerate(f, 1):
                    line_esc = line.rstrip().replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
                    if i in executable:
                        if i in missed_set:
                            html.append(f'<span class="miss">{i:>4}  {line_esc}</span>')
                        else:
                            html.append(f'<span class="hit">{i:>4}  {line_esc}</span>')
                    else:
                        html.append(f'{i:>4}  {line_esc}')
        except (IOError, OSError):
            html.append('(could not read source)')
        html.append('</pre>')

    html.append('</body></html>')
    return '\n'.join(html)


def _parse_report_dt(filename: str):
    """Parse YYYY_MM_DD_HH_MM_SS from a report filename, return datetime or None."""
    stem = filename[:-5] if filename.endswith('.html') else filename
    try:
        return datetime.datetime.strptime(stem, '%Y_%m_%d_%H_%M_%S')
    except ValueError:
        return None


def _format_display_date(dt: datetime.datetime) -> str:
    """Format as 'Month D, YYYY, HH:MM' (24-hour)."""
    return f'{dt.strftime("%B")} {dt.day}, {dt.year}, {dt.strftime("%H:%M")}'


def regenerate_index(coverage_dir: str) -> None:
    """Rewrite coverage/index.html as a horizontal nav + iframe."""
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
<html><head>
<meta charset="utf-8">
<title>ptyunit coverage</title>
<style>
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{ font-family: monospace; background: #1a1a1a; color: #e0e0e0; display: flex; flex-direction: column; height: 100vh; }}
nav {{ background: #2a2a2a; border-bottom: 1px solid #444; padding: 8px 12px; overflow-x: auto; white-space: nowrap; flex-shrink: 0; }}
nav a {{ display: inline-block; color: #7af; text-decoration: none; padding: 4px 10px; margin-right: 4px; border-radius: 3px; border: 1px solid #444; }}
nav a:hover {{ background: #3a3a3a; }}
iframe {{ flex: 1; border: none; width: 100%; }}
</style>
</head><body>
<nav>
  {links}
</nav>
<iframe name="report" src="{latest}"></iframe>
</body></html>'''

    with open(os.path.join(coverage_dir, 'index.html'), 'w') as f:
        f.write(html)


def main():
    parser = argparse.ArgumentParser(description='ptyunit coverage report')
    parser.add_argument('--trace', required=True, help='Path to xtrace output file')
    parser.add_argument('--src', required=True, help='Source directory to measure')
    parser.add_argument('--format', default='text', choices=['text', 'json', 'html'])
    parser.add_argument('--min', type=float, default=0, help='Minimum coverage %% (exit 1 if below)')
    args = parser.parse_args()

    hits = parse_trace(args.trace, args.src)
    results = compute_coverage(args.src, hits)

    if args.format == 'text':
        print(format_text(results))
    elif args.format == 'json':
        print(format_json(results))
    elif args.format == 'html':
        os.makedirs('coverage', exist_ok=True)
        timestamp = datetime.datetime.now().strftime('%Y_%m_%d_%H_%M_%S')
        report_name = f'{timestamp}.html'
        report_path = os.path.join('coverage', report_name)
        html = format_html(results, args.src)
        with open(report_path, 'w') as f:
            f.write(html)
        print(f'HTML coverage report written to {report_path}')
        regenerate_index('coverage')
        # Also print text summary
        print(format_text(results))

    # Check minimum coverage
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
