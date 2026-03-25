"""conftest.py — adds repo root to sys.path so pty_session and pty_run are importable."""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
