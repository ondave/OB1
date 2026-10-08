"""Tests for ops/ob-dream-review.py. Run: uvx pytest ops/tests -q"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "ob-dream-review.py"
spec = importlib.util.spec_from_file_location("ob_dream_review", SCRIPT)
assert spec and spec.loader
review = importlib.util.module_from_spec(spec)
# Register before executing: @dataclass resolves string annotations through
# sys.modules[cls.__module__], which is None for an unregistered module.
sys.modules["ob_dream_review"] = review
spec.loader.exec_module(review)


def report(*items: str) -> str:
    return (
        "DREAM 2026-10-09 NIGHTLY\nactions:\n- none\nREVIEW\n"
        + "".join(f"{i}\n" for i in items)
        + "END\n"
    )


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        (report("thought:aaaa1111\tdup of x"), {"thought:aaaa1111": "dup of x"}),
        (report("step:bbbb2222 stale 90 days"), {"step:bbbb2222": "stale 90 days"}),
        (report(), {}),
        ("DREAM ...\nkept-for-review:\n- x\n", None),
        ("REVIEW\nthought:a\tx\n", None),  # truncated: no END
    ],
)
def test_parse_review(text: str, expected: dict[str, str] | None) -> None:
    assert review.parse_review(text) == expected


def test_diff_new_carried_resolved() -> None:
    state = {
        "a": review.Entry("2026-10-01", "2026-10-08", 8, "old"),
        "gone": review.Entry("2026-10-01", "2026-10-08", 8, "fixed since"),
    }
    new_state, new, carried, resolved = review.diff(
        state, {"a": "still", "b": "fresh"}, "2026-10-09"
    )
    assert new == ["b"] and carried == ["a"] and resolved == ["gone"]
    assert new_state["a"] == review.Entry("2026-10-01", "2026-10-09", 9, "still")
    assert new_state["b"] == review.Entry("2026-10-09", "2026-10-09", 1, "fresh")


def run(
    tmp: Path, text: str, today: str, *extra: str
) -> subprocess.CompletedProcess[str]:
    (tmp / "report.txt").write_text(text)
    pre = tmp / "precheck.tsv"
    if not pre.exists():
        pre.write_text("")
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--report",
            str(tmp / "report.txt"),
            "--precheck",
            str(pre),
            "--state-dir",
            str(tmp / "state"),
            "--today",
            today,
            *extra,
        ],
        capture_output=True,
        check=False,
        text=True,
    )


def test_two_nights_then_resolution(tmp_path: Path) -> None:
    r1 = run(
        tmp_path, report("item:11111111\tstale", "project:foo\tidle"), "2026-10-08"
    )
    assert r1.returncode == 0
    assert "2 new, 0 carried" in r1.stdout
    digest = (tmp_path / "state" / "digest.txt").read_text()
    assert "2 new review item(s)" in digest and "item:11111111: stale" in digest

    r2 = run(tmp_path, report("item:11111111\tstale"), "2026-10-09")
    assert "0 new, 1 carried" in r2.stdout and "RESOLVED project:foo" in r2.stdout
    state = json.loads((tmp_path / "state" / "review.json").read_text())
    assert state == {
        "item:11111111": {
            "first_seen": "2026-10-08",
            "last_seen": "2026-10-09",
            "nights": 2,
            "reason": "stale",
        }
    }
    # Nothing new and no precheck findings: the digest is quiet.
    assert (tmp_path / "state" / "digest.txt").read_text().endswith("Nothing new.\n")


def test_aging_reaches_digest(tmp_path: Path) -> None:
    state_dir = tmp_path / "state"
    state_dir.mkdir()
    (state_dir / "review.json").write_text(
        json.dumps(
            {
                "step:22222222": {
                    "first_seen": "2026-09-20",
                    "last_seen": "2026-10-08",
                    "nights": 13,
                    "reason": "old",
                }
            }
        )
    )
    r = run(tmp_path, report("step:22222222\told"), "2026-10-09")
    assert "AGING    step:22222222\t14 nights since 2026-09-20" in r.stdout
    assert (
        "1 item(s) flagged 14+ nights running" in (state_dir / "digest.txt").read_text()
    )


def test_dry_run_writes_nothing(tmp_path: Path) -> None:
    r = run(tmp_path, report("item:33333333\tx"), "2026-10-09", "--dry-run")
    assert r.returncode == 0 and "1 new" in r.stdout
    assert not (tmp_path / "state").exists()


def test_missing_block_keeps_state_and_warns(tmp_path: Path) -> None:
    run(tmp_path, report("item:44444444\tx"), "2026-10-08")
    before = (tmp_path / "state" / "review.json").read_text()
    r = run(tmp_path, "claude crashed\n", "2026-10-09")
    assert r.returncode == 2
    assert (tmp_path / "state" / "review.json").read_text() == before
    assert "no REVIEW block" in (tmp_path / "state" / "digest.txt").read_text()


def test_precheck_findings_in_digest_without_values(tmp_path: Path) -> None:
    (tmp_path / "precheck.tsv").write_text(
        "SECRET\tprojects\teidos\tlinear\nDEADPATH\ts57-vector-tiles\t/home/dave/Dev/s57-vector-tiles\n"
    )
    run(tmp_path, report(), "2026-10-09")
    digest = (tmp_path / "state" / "digest.txt").read_text()
    assert "SECURITY: 1 row(s)" in digest and "projects eidos (linear)" in digest
    assert (
        "deadpath:s57-vector-tiles: repo path no longer exists: /home/dave/Dev/s57-vector-tiles"
        in digest
    )

    # Second night: the secret repeats on purpose, the dead path does not.
    run(tmp_path, report(), "2026-10-10")
    digest = (tmp_path / "state" / "digest.txt").read_text()
    assert "SECURITY: 1 row(s)" in digest
    assert "deadpath" not in digest


def test_dead_path_alone_goes_quiet_after_first_night(tmp_path: Path) -> None:
    (tmp_path / "precheck.tsv").write_text("DEADPATH\tfoo\t/gone\n")
    run(tmp_path, report(), "2026-10-09")
    assert "deadpath:foo" in (tmp_path / "state" / "digest.txt").read_text()
    r = run(tmp_path, report(), "2026-10-10")
    assert "0 new, 1 carried" in r.stdout
    assert (tmp_path / "state" / "digest.txt").read_text().endswith("Nothing new.\n")


def test_bullet_keys_are_stable() -> None:
    assert review.parse_review(report("- item:cccccccc\tx", "* step:dddddddd y")) == {
        "item:cccccccc": "x",
        "step:dddddddd": "y",
    }


def test_corrupt_state_is_moved_aside_and_reported(tmp_path: Path) -> None:
    state_dir = tmp_path / "state"
    state_dir.mkdir()
    (state_dir / "review.json").write_text("{not json")
    r = run(tmp_path, report("item:55555555\tx"), "2026-10-09")
    assert r.returncode == 0
    assert (state_dir / "review.json.corrupt-2026-10-09").read_text() == "{not json"
    assert "1 new" in r.stdout
    assert "was unreadable" in (state_dir / "digest.txt").read_text()


def test_corrupt_state_left_alone_on_dry_run(tmp_path: Path) -> None:
    state_dir = tmp_path / "state"
    state_dir.mkdir()
    (state_dir / "review.json").write_text("{not json")
    r = run(tmp_path, report("item:66666666\tx"), "2026-10-09", "--dry-run")
    assert r.returncode == 0
    assert (state_dir / "review.json").read_text() == "{not json"
    assert not (state_dir / "digest.txt").exists()


@pytest.mark.parametrize(
    ("flag", "text"),
    [("NOBACKUP", "ran as a DRY RUN"), ("PRECHECKFAILED", "The precheck failed")],
)
def test_flags_reach_digest(tmp_path: Path, flag: str, text: str) -> None:
    (tmp_path / "precheck.tsv").write_text(f"{flag}\n")
    run(tmp_path, report(), "2026-10-09")
    assert text in (tmp_path / "state" / "digest.txt").read_text()
