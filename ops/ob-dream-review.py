#!/usr/bin/env python3
"""Compare tonight's dream REVIEW block with previous nights and write a digest.

Called by ob-dream.sh after the model's report. The model never touches files;
this script owns the state:

  <state-dir>/review.json   {key: {first_seen, last_seen, nights, reason}}
  <state-dir>/digest.txt    a few lines for the fable-mode SessionStart hook

The summary for dream.log goes to stdout. With --dry-run nothing is written.
Exit 0 on success, 2 when the report has no REVIEW block (state left alone, but
the digest still records the failure so it is seen at session start).
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path

AGING_NIGHTS = 14
DIGEST_MAX_NEW = 5


@dataclass
class Entry:
    first_seen: str
    last_seen: str
    nights: int
    reason: str


def parse_review(report: str) -> dict[str, str] | None:
    """Return {key: reason} from the REVIEW ... END block, or None if absent."""
    lines = report.splitlines()
    try:
        start = max(i for i, ln in enumerate(lines) if ln.strip() == "REVIEW")
    except ValueError:
        return None
    items: dict[str, str] = {}
    for ln in lines[start + 1 :]:
        if ln.strip() == "END":
            return items
        if not ln.strip():
            continue
        # A bullet ("- key") would make the key unstable night to night.
        line = ln.strip().removeprefix("- ").removeprefix("* ")
        key, _, reason = line.partition("\t")
        if not reason:  # tolerate a model that used spaces instead of a tab
            key, _, reason = line.partition(" ")
        items[key.strip()] = reason.strip()
    return None  # REVIEW without END: treat as truncated


@dataclass
class Precheck:
    secrets: list[str]
    deadpaths: dict[str, str]  # slug -> path
    flags: set[str]  # NOBACKUP, PRECHECKFAILED


def parse_precheck(text: str) -> Precheck:
    pre = Precheck([], {}, set())
    for ln in text.splitlines():
        parts = ln.split("\t")
        if parts[0] == "SECRET" and len(parts) == 4:
            pre.secrets.append(f"{parts[1]} {parts[2]} ({parts[3]})")
        elif parts[0] == "DEADPATH" and len(parts) == 3:
            pre.deadpaths[parts[1]] = parts[2]
        elif parts[0] in {"NOBACKUP", "PRECHECKFAILED"}:
            pre.flags.add(parts[0])
    return pre


def load_state(
    path: Path, today: str, *, dry_run: bool = False
) -> tuple[dict[str, Entry], str | None]:
    """Return (state, warning). A corrupt file is moved aside, never fatal.

    A dry run leaves a corrupt file where it is and just starts empty.
    """
    if not path.exists():
        return {}, None
    try:
        raw = json.loads(path.read_text())
        return {k: Entry(**v) for k, v in raw.items()}, None
    except (ValueError, TypeError, AttributeError):
        if dry_run:
            return {}, None
        aside = path.with_name(f"review.json.corrupt-{today}")
        path.replace(aside)
        return (
            {},
            f"review.json was unreadable and was moved to {aside.name}; history restarts tonight.",
        )


def diff(
    state: dict[str, Entry], current: dict[str, str], today: str
) -> tuple[dict[str, Entry], list[str], list[str], list[str]]:
    """Return (new_state, new_keys, carried_keys, resolved_keys)."""
    new_state: dict[str, Entry] = {}
    new_keys, carried = [], []
    for key, reason in current.items():
        old = state.get(key)
        if old is None:
            new_state[key] = Entry(today, today, 1, reason)
            new_keys.append(key)
        else:
            new_state[key] = Entry(old.first_seen, today, old.nights + 1, reason)
            carried.append(key)
    resolved = sorted(set(state) - set(current))
    return new_state, new_keys, carried, resolved


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", type=Path, required=True)
    ap.add_argument("--precheck", type=Path, required=True)
    ap.add_argument("--state-dir", type=Path, required=True)
    ap.add_argument("--mode", default="NIGHTLY")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--today", default=datetime.now().astimezone().date().isoformat())
    args = ap.parse_args()

    report = args.report.read_text() if args.report.exists() else ""
    precheck = args.precheck.read_text() if args.precheck.exists() else ""
    pre = parse_precheck(precheck)
    current = parse_review(report)
    state_path = args.state_dir / "review.json"
    state, state_warning = load_state(state_path, args.today, dry_run=args.dry_run)

    digest = [f"Open Brain dream {args.today} ({args.mode})"]
    # Secrets repeat every night on purpose until the row is fixed.
    if pre.secrets:
        digest.append(
            f"SECURITY: {len(pre.secrets)} row(s) hold credential-shaped strings; "
            "revoke the credential, then edit the row:"
        )
        digest += [f"  {s}" for s in pre.secrets]
    if "NOBACKUP" in pre.flags:
        digest.append(
            "No backup in the last 26 h, so tonight's dream ran as a DRY RUN "
            "(check `systemctl --user status ob1-backup` and ops/backup.log)."
        )
    if "PRECHECKFAILED" in pre.flags:
        digest.append(
            "The precheck failed (DB unreachable?): secrets and repo paths were not scanned."
        )
    if state_warning:
        digest.append(state_warning)

    if current is None:
        if pre.deadpaths:
            digest.append(f"{len(pre.deadpaths)} project repo path(s) no longer exist:")
            digest += [f"  {s}: {p}" for s, p in pre.deadpaths.items()]
        print(
            "=== review diff: no complete REVIEW block in the report; state unchanged ==="
        )
        digest.append(
            "The dream report had no REVIEW block (failed or truncated run?): see ops/dream.log."
        )
        rc = 2
    else:
        # Dead paths go through the same diff, so they surface once (and again
        # when aging) instead of every night.
        for slug, path in pre.deadpaths.items():
            current.setdefault(
                f"deadpath:{slug}", f"repo path no longer exists: {path}"
            )
        new_state, new_keys, carried, resolved = diff(state, current, args.today)
        aging = sorted(k for k in carried if new_state[k].nights >= AGING_NIGHTS)
        print(
            f"=== review diff: {len(new_keys)} new, {len(carried)} carried "
            f"({len(aging)} for {AGING_NIGHTS}+ nights), {len(resolved)} resolved ==="
        )
        for k in new_keys:
            print(f"NEW      {k}\t{current[k]}")
        for k in aging:
            e = new_state[k]
            print(f"AGING    {k}\t{e.nights} nights since {e.first_seen}\t{e.reason}")
        for k in resolved:
            print(f"RESOLVED {k}")
        if new_keys:
            digest.append(f"{len(new_keys)} new review item(s):")
            digest += [f"  {k}: {current[k]}" for k in new_keys[:DIGEST_MAX_NEW]]
            if len(new_keys) > DIGEST_MAX_NEW:
                digest.append(
                    f"  ... and {len(new_keys) - DIGEST_MAX_NEW} more in ops/dream.log"
                )
        if aging:
            digest.append(
                f"{len(aging)} item(s) flagged {AGING_NIGHTS}+ nights running: "
                "decide or record them (see AGING in ops/dream.log)."
            )
        if not args.dry_run:
            args.state_dir.mkdir(parents=True, exist_ok=True)
            tmp = state_path.with_suffix(".tmp")
            tmp.write_text(
                json.dumps({k: asdict(v) for k, v in new_state.items()}, indent=1)
            )
            tmp.replace(state_path)
        rc = 0

    if not args.dry_run:
        args.state_dir.mkdir(parents=True, exist_ok=True)
        quiet = len(digest) == 1
        (args.state_dir / "digest.txt").write_text(
            "\n".join(digest + (["Nothing new."] if quiet else [])) + "\n"
        )
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
