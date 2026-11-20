"""Locations shared by the offline converters. Paths are independent of the caller's cwd."""
import os
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


def project_path(relative=""):
    root = Path(os.environ.get("POKESAGA_PROJECT", REPO)).expanduser().resolve()
    return str(root / relative)


def source_path(name, relative=""):
    sources = Path(os.environ.get("POKESAGA_SOURCES", REPO.parent / "pokesaga-sources"))
    root = Path(os.environ.get("POKESAGA_" + name.upper(), sources / name))
    return str(root.expanduser().resolve() / relative)


def cache_path(relative):
    root = Path(os.environ.get("POKESAGA_CACHE", Path.home() / ".cache" / "pokesaga"))
    root = root.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    return str(root / relative)
