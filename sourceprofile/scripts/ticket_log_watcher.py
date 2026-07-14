#!/usr/bin/env python3
"""
Watch ticket logs directories: number new .log files with an incrementing
two-digit prefix (01-, 02-, ...) and keep current.log symlinked to the latest.

Also watches ~/tickets for new .xml files (e.g. HOT-123456.xml) and moves them
to project subdirs (e.g. HOT/HOT-123456/HOT-123456.xml).

Each directory is processed independently with its own counter.
Single-instance: only one watcher runs at a time (lock file).
Poll interval: 1 second (faster reaction to new files).

Files are only numbered after unchanged for STABILITY_SEC (avoids one logical
file becoming many when the same path is rewritten repeatedly). Temp/incomplete
downloads (.crdownload, .tmp, .part, etc.) are never numbered.

Usage:
  python ticket_log_watcher.py [LOGS_DIR ...]
  python ticket_log_watcher.py --force   # kill existing instance and run
  # or after migrating to ~/.sourceprofile/scripts/:
  ticket_log_watcher [LOGS_DIR ...]

Default LOGS_DIRs: ~/today/logs ~/git/empliment/tickets/current-ticket/logs
"""

from __future__ import annotations

import argparse
import fcntl
import logging
import os
import re
import signal
import subprocess
import sys
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path


DEFAULT_LOGS_DIRS = [
    Path.home() / "today/logs",
    Path.home() / "git/empliment/tickets/current-ticket/logs",
]
TICKETS_DIR = Path.home() / "tickets"
# e.g. HOT-123456.xml -> HOT/HOT-123456/HOT-123456.xml
TICKET_XML_RE = re.compile(r"^([A-Za-z]+)-\d+\.xml$", re.IGNORECASE)
CURRENT_LOG_NAME = "current.log"
SCAN_INTERVAL_SEC = 1
NUMBERED_PREFIX_RE = re.compile(r"^(\d{2})-(.+)$")
# Meta files to never number or use when computing next number
IGNORED_FILES = frozenset({".DS_Store", "Thumbs.db", "desktop.ini", ".directory"})
# Temp/incomplete download extensions (e.g. Chrome .crdownload) - never number
IGNORED_EXTENSIONS = frozenset({".crdownload", ".tmp", ".temp", ".part", ".download", ".!ut"})
# Only number files that haven't been modified for this many seconds (avoids splitting one logical file into many)
STABILITY_SEC = 2
LOCK_PATH = Path("/tmp/ticket-log-watcher.lock")
WATCHER_LOG_PATH = Path("/tmp/ticket-log-watcher.log")
LOG_DATE_FMT = "%Y-%m-%d %H:%M:%S"
LOG_MAX_BYTES = 512 * 1024  # 500KB; file rotates when exceeded
LOG_BACKUP_COUNT = 2  # keep .log.1 and .log.2 after rotation

def _setup_logging() -> logging.Logger:
    """Log to stderr (INFO) and rotating file (DEBUG). Same yyyy-mm-dd format on both."""
    log = logging.getLogger("ticket_log_watcher")
    log.setLevel(logging.DEBUG)
    log.handlers.clear()
    file_fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s", datefmt=LOG_DATE_FMT)
    stream_fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s", datefmt=LOG_DATE_FMT)
    try:
        fh = RotatingFileHandler(
            WATCHER_LOG_PATH,
            maxBytes=LOG_MAX_BYTES,
            backupCount=LOG_BACKUP_COUNT,
            encoding="utf-8",
        )
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(file_fmt)
        log.addHandler(fh)
    except OSError:
        pass
    eh = logging.StreamHandler(sys.stderr)
    eh.setLevel(logging.INFO)
    eh.setFormatter(stream_fmt)
    log.addHandler(eh)
    return log


def _read_pid_from_lock_file() -> int | None:
    """Read PID stored in lock file. Caller may use this when lock is held by another process."""
    try:
        with open(LOCK_PATH, "rb") as f:
            data = f.read().decode().strip()
            if data and data.isdigit():
                return int(data)
    except OSError:
        pass
    return None


def _kill_other_watcher_processes() -> None:
    """Kill any other processes running this script (e.g. old instances that don't write PID to lock)."""
    my_pid = os.getpid()
    try:
        out = subprocess.run(
            ["pgrep", "-f", "ticket_log_watcher"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if out.returncode not in (0, 1):
            return
        for line in out.stdout.splitlines():
            line = line.strip()
            if not line or not line.isdigit():
                continue
            pid = int(line)
            if pid == my_pid:
                continue
            try:
                os.kill(pid, signal.SIGTERM)
            except (OSError, ProcessLookupError):
                pass
    except (subprocess.TimeoutExpired, FileNotFoundError, ValueError):
        pass


def _try_acquire_lock() -> int | None:
    """Try to acquire exclusive lock. Returns fd or None if already locked."""
    try:
        fd = os.open(LOCK_PATH, os.O_CREAT | os.O_RDWR, 0o600)
    except OSError:
        return None
    try:
        fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.ftruncate(fd, 0)
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, str(os.getpid()).encode())
        os.fsync(fd)
        return fd
    except OSError:
        os.close(fd)
        return None


def acquire_lock(*, force: bool = False) -> int | None:
    """Try to acquire exclusive lock. Returns fd or None if already locked.
    If force is True and lock is held, kills the holder (by PID in lock file, or by
    finding other ticket_log_watcher processes) and retries.
    """
    fd = _try_acquire_lock()
    if fd is not None:
        return fd
    if not force:
        return None
    # Prefer killing PID from lock file (current script writes it)
    pid = _read_pid_from_lock_file()
    if pid is not None and pid != os.getpid():
        try:
            os.kill(pid, signal.SIGTERM)
        except (OSError, ProcessLookupError):
            pass
    else:
        # Lock file had no PID (old watcher or race): kill any process running this script
        _kill_other_watcher_processes()
    for _ in range(3):
        time.sleep(1)
        fd = _try_acquire_lock()
        if fd is not None:
            return fd
    return None


def release_lock(fd: int) -> None:
    try:
        fcntl.lockf(fd, fcntl.LOCK_UN)
    finally:
        os.close(fd)


def get_next_number(logs_dir: Path) -> int:
    """Derive the next number from existing numbered files in the directory.
    
    Always scans the directory to find the largest existing two-digit prefix,
    ensuring we stay up-to-date even when directories are replaced daily.
    Returns largest prefix + 1, or 1 if none exist.
    """
    max_n = 0
    try:
        for p in logs_dir.iterdir():
            # Skip symlinks (like current.log) and non-files
            if p.is_symlink():
                continue
            if not p.is_file():
                continue
            m = NUMBERED_PREFIX_RE.match(p.name)
            if m:
                base_name = m.group(2)
                if base_name in IGNORED_FILES:
                    continue
                if _should_ignore_file(p):
                    continue
                max_n = max(max_n, int(m.group(1)))
    except OSError:
        # Directory doesn't exist or can't be read
        pass
    return max_n + 1


def _should_ignore_file(p: Path) -> bool:
    """True if file should be ignored (temp download, meta, etc.)."""
    if p.name in IGNORED_FILES:
        return True
    suf = p.suffix.lower()
    if suf in IGNORED_EXTENSIONS:
        return True
    # e.g. file.crdownload has suffix .crdownload
    if any(p.name.lower().endswith(ext) for ext in IGNORED_EXTENSIONS):
        return True
    return False


def get_unnumbered_logs(logs_dir: Path) -> list[Path]:
    """Log files that don't have a two-digit prefix. Excludes current.log, meta files,
    temp/incomplete downloads, and files still being written (mtime within STABILITY_SEC).
    """
    unnumbered: list[Path] = []
    now = time.time()
    try:
        for p in logs_dir.iterdir():
            if p.name == CURRENT_LOG_NAME:
                continue
            if _should_ignore_file(p):
                continue
            if p.is_symlink():
                continue
            if not p.is_file():
                continue
            if NUMBERED_PREFIX_RE.match(p.name):
                continue
            # Skip files modified too recently (same logical file written repeatedly)
            try:
                if (now - p.stat().st_mtime) < STABILITY_SEC:
                    continue
            except OSError:
                continue
            unnumbered.append(p)
        unnumbered.sort(key=lambda p: p.stat().st_mtime)
    except OSError:
        # Directory doesn't exist or can't be read
        pass
    return unnumbered


def process_logs_dir(logs_dir: Path, log: logging.Logger) -> None:
    """Process a single logs directory: number unnumbered files and update current.log symlink.

    This function is called independently for each watched directory.
    """
    if not logs_dir.is_dir():
        return

    # Always derive the next number from current directory contents
    unnumbered = get_unnumbered_logs(logs_dir)
    next_num = get_next_number(logs_dir)
    latest_numbered: Path | None = None

    for p in unnumbered:
        new_name = f"{next_num:02d}-{p.name}"
        new_path = logs_dir / new_name
        if new_path.exists():
            next_num += 1
            continue
        try:
            p.rename(new_path)
            latest_numbered = new_path
            log.info("numbered %s -> %s in %s", p.name, new_name, logs_dir)
            next_num += 1
        except OSError:
            pass

    # Update current.log symlink to point to latest numbered file
    target = latest_numbered
    if target is None:
        try:
            numbered = [
                q
                for q in logs_dir.iterdir()
                if q.is_file() and not q.is_symlink() and NUMBERED_PREFIX_RE.match(q.name)
            ]
            numbered.sort(key=lambda q: int(NUMBERED_PREFIX_RE.match(q.name).group(1)))
            if numbered:
                target = numbered[-1]
        except OSError:
            pass

    if target is not None:
        current_link = logs_dir / CURRENT_LOG_NAME
        tmp_link: Path | None = None
        try:
            # Avoid unlink+symlink: two steps race with another watcher or tool that
            # recreates current.log, producing FileExistsError: 'NN-...' -> '.../current.log'.
            tmp_link = logs_dir / f".current.log.{os.getpid()}.{time.time_ns()}"
            tmp_link.symlink_to(target.name)
            tmp_link.replace(current_link)
            log.debug("current.log -> %s in %s", target.name, logs_dir)
        except OSError as e:
            log.warning("failed to update current.log in %s: %s", logs_dir, e)
        finally:
            if tmp_link is not None:
                try:
                    tmp_link.unlink(missing_ok=True)
                except OSError:
                    pass


def get_new_ticket_xmls(tickets_dir: Path) -> list[Path]:
    """XML files in tickets_dir that match PROJECT-NUMBER.xml and are stable (not recently modified)."""
    new_xmls: list[Path] = []
    now = time.time()
    try:
        for p in tickets_dir.iterdir():
            if not p.is_file() or p.is_symlink():
                continue
            if p.suffix.lower() != ".xml":
                continue
            if _should_ignore_file(p):
                continue
            if not TICKET_XML_RE.match(p.name):
                continue
            try:
                if (now - p.stat().st_mtime) < STABILITY_SEC:
                    continue
            except OSError:
                continue
            new_xmls.append(p)
        new_xmls.sort(key=lambda p: p.stat().st_mtime)
    except OSError:
        pass
    return new_xmls


def process_tickets_dir(tickets_dir: Path, log: logging.Logger) -> None:
    """Move new ticket XML files (e.g. HOT-123456.xml) to project subdirs (e.g. HOT/HOT-123456/HOT-123456.xml)."""
    if not tickets_dir.is_dir():
        return

    for p in get_new_ticket_xmls(tickets_dir):
        m = TICKET_XML_RE.match(p.name)
        if not m:
            continue
        prefix = m.group(1)
        ticket_id = p.stem  # e.g. HOT-123456
        dest_dir = tickets_dir / prefix / ticket_id
        dest_path = dest_dir / p.name
        if dest_path.exists():
            log.warning("destination already exists, skipping: %s", dest_path)
            continue
        try:
            dest_dir.mkdir(parents=True, exist_ok=True)
            p.rename(dest_path)
            log.info("moved ticket %s -> %s", p.name, dest_path)
        except OSError as e:
            log.warning("failed to move %s: %s", p, e)


def run_watcher(watch_paths: list[Path], force: bool, log: logging.Logger) -> None:
    """Watch multiple paths, each may be a symlink (e.g. ~/today/logs) that gets replaced daily.

    Each path is processed independently with its own counter.
    We re-resolve symlinks on each scan to stay up-to-date when they change.
    """
    watch_paths = [p.expanduser() for p in watch_paths]
    for watch_path in watch_paths:
        if not watch_path.exists() and not watch_path.is_symlink():
            log.warning("Path does not exist: %s", watch_path)

    lock_fd = acquire_lock(force=force)
    if lock_fd is None:
        log.error("Another instance is already running. Use --force to kill it and take over.")
        sys.exit(1)

    tickets_path = TICKETS_DIR.expanduser()
    if not tickets_path.exists() and not tickets_path.is_symlink():
        log.warning("Tickets path does not exist: %s", tickets_path)

    log.info("watcher started (pid=%s), interval=%ss, watching %s + %s", os.getpid(), SCAN_INTERVAL_SEC, watch_paths, tickets_path)
    try:
        while True:
            t0 = time.monotonic()
            for watch_path in watch_paths:
                try:
                    logs_dir = watch_path.resolve(strict=True)
                except (OSError, RuntimeError):
                    continue
                process_logs_dir(logs_dir, log)
            try:
                tickets_dir = tickets_path.resolve(strict=True)
                process_tickets_dir(tickets_dir, log)
            except (OSError, RuntimeError):
                pass
            elapsed = time.monotonic() - t0
            if elapsed > 0.5:
                log.debug("cycle took %.2fs for %s", elapsed, watch_paths)
            time.sleep(SCAN_INTERVAL_SEC)
    finally:
        release_lock(lock_fd)
        log.info("watcher stopped")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[1].split("Usage:")[0].strip())
    parser.add_argument(
        "logs_dirs",
        nargs="*",
        type=Path,
        default=None,
        help=f"Logs directories (default: {', '.join(str(p) for p in DEFAULT_LOGS_DIRS)})",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Kill existing watcher instance (if any) and take over.",
    )
    args = parser.parse_args()
    logs_dirs = args.logs_dirs if args.logs_dirs else DEFAULT_LOGS_DIRS
    log = _setup_logging()
    run_watcher(logs_dirs, force=args.force, log=log)
