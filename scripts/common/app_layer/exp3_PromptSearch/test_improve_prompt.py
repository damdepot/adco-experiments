"""Unit tests for the prompt-improvement helpers (no LLM calls).

Covers fence stripping, bullet-only parsing, the case-insensitive
word-boundary denylist, offending-bullet removal and both caps.
"""

import sys
import os
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))

from improve_prompt import (  # noqa: E402
    apply_caps,
    drop_violations,
    failure_summary,
    find_violations,
    guidance_bytes,
    parse_guidance,
    strip_fences,
    summarize_smoke_log,
)


def test_strip_fences_removes_a_whole_fence():
    assert strip_fences("```\n- a\n- b\n```") == "- a\n- b"
    assert strip_fences("```markdown\n- a\n```") == "- a"
    # Prose that merely contains a fence is not "wholly fenced".
    text = "- a\n```\nx\n```"
    assert strip_fences(text) == text
    assert strip_fences("- a") == "- a"


def test_parse_guidance_drops_preamble_and_normalizes_stars():
    text = (
        "Here is the rewritten guidance:\n\n"
        "* first rule\n"
        "  continued detail\n"
        "- second rule\n\n"
        "Hope this helps.\n"
    )
    assert parse_guidance(text) == [
        "- first rule",
        "  continued detail",
        "- second rule",
    ]


def test_parse_guidance_of_a_fenced_response():
    assert parse_guidance("```\n- only rule\n```") == ["- only rule"]


def test_find_violations_is_case_insensitive_and_word_bounded():
    tokens = ["warehouse"]
    assert find_violations("- Keep each Warehouse row once.", tokens) == tokens
    # Plural is a different word: not a violation.
    assert find_violations("- Avoid per-warehouses scans.", tokens) == []
    # A hyphen is a word boundary.
    assert find_violations("- multi-warehouse batching", tokens) == tokens
    assert find_violations("- anything", []) == []


def test_drop_violations_removes_whole_bullet():
    lines = [
        "- Keep general rules.",
        "- Cache Warehouse lookups.",
        "  extra warehouse note",
        "- Preserve behavior.",
    ]
    kept, dropped = drop_violations(lines, ["warehouse"])
    assert kept == ["- Keep general rules.", "- Preserve behavior."]
    assert dropped == ["- Cache Warehouse lookups.", "  extra warehouse note"]


def test_drop_violations_checks_continuation_lines():
    lines = ["- Use caches.", "  e.g. warehouse cache", "- Preserve behavior."]
    kept, dropped = drop_violations(lines, ["warehouse"])
    assert kept == ["- Preserve behavior."]
    assert dropped == ["- Use caches.", "  e.g. warehouse cache"]


def test_apply_caps_limits_bullets():
    lines = ["- a", "  more a", "- b", "- c"]
    out, truncated = apply_caps(lines, 2, 4096)
    assert out == ["- a", "  more a", "- b"] and truncated is True
    out, truncated = apply_caps(lines, 10, 4096)
    assert out == lines and truncated is False


def test_apply_caps_limits_bytes():
    lines = ["- aaaa", "- bbbb"]
    # "- aaaa\n" is 7 bytes, so only the first bullet fits in 7 bytes.
    out, truncated = apply_caps(lines, 25, 7)
    assert out == ["- aaaa"] and truncated is True
    assert guidance_bytes(out) == 7
    out, truncated = apply_caps(lines, 25, 4096)
    assert out == lines and truncated is False


def test_failure_summary_reads_verifier_checks_dict():
    feedback = {
        "rewrite_status": "ok",
        "rewrite_log_tail": "",
        "smoke_errors": ["WARNING: Failed: cannot compare smallint and integer"],
        "verify": {
            "status": "FAIL",
            "checks": {
                "static": {"status": "PASS", "issues": []},
                "invariants": {"status": "FAIL", "issues": ["CC2: gap"]},
            },
        },
    }
    summary = failure_summary(feedback)
    assert "invariants [FAIL]: CC2: gap" in summary, summary
    assert "static" not in summary, summary
    assert "cannot compare smallint and integer" in summary, summary


def test_summarize_smoke_log_dedupes_timestamps_and_counts():
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "smoke.log"
        repeated = (
            "11-12-2026 11:56:{:02d} [execute:070] WARNING: Failed to execute "
            "Transaction 'NEW_ORDER': cannot compare dissimilar column types "
            "smallint and integer at record column 2\n\n"
        )
        path.write_text(
            "".join(repeated.format(13 + i) for i in range(20))
            + "11-12-2026 11:56:50 [execute:070] WARNING: Failed to execute "
            "Transaction 'PAYMENT': not enough arguments for format string\n\n",
            encoding="utf-8",
        )
        out = summarize_smoke_log(str(path))
        assert len(out) == 2, out
        assert "smallint and integer" in out[0] and out[0].endswith("(x20)"), out
        assert "PAYMENT" in out[1], out


def test_summarize_smoke_log_folds_traceback():
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "smoke.log"
        path.write_text(
            "Traceback (most recent call last):\n"
            '  File "tpcc.py", line 10, in <module>\n'
            "KeyError: 'getItemInfo'\n"
            "\n",
            encoding="utf-8",
        )
        out = summarize_smoke_log(str(path))
        assert len(out) == 1, out
        assert "Traceback" in out[0] and "KeyError" in out[0], out


def test_summarize_smoke_log_missing_file():
    assert summarize_smoke_log("/nonexistent/smoke.log") == []


if __name__ == "__main__":
    failed = 0
    for name in sorted(globals()):
        func = globals()[name]
        if name.startswith("test_") and callable(func):
            try:
                func()
                print(f"PASS {name}")
            except AssertionError as exc:
                failed += 1
                print(f"FAIL {name}: {exc}")
    print(f"{failed} failure(s)")
    sys.exit(1 if failed else 0)
