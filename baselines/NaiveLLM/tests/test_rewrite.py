import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.rewrite import TASK, RULES, build_prompt, parse_response, safe_target, select_files

PROMPTS_DIR = Path(__file__).resolve().parents[1] / "prompts"


def _sample_output_dir(tmp: str) -> Path:
    d = Path(tmp)
    (d / "drivers").mkdir()
    (d / "drivers" / "postgresdriver.py").write_text("x = 1\n")
    (d / "tpcc.py").write_text("print('hi')\n")
    (d / "tpcc.postgres.sql").write_text("CREATE TABLE t();\n")
    return d


def _build(d: Path, guidance=None) -> str:
    rewrite, context = select_files(d, "postgres")
    return build_prompt(d, rewrite, context, guidance)


def test_parse_response():
    sample = (
        "preamble text\n"
        "### FILE: drivers/postgresdriver.py\n"
        "```python\n"
        "x = 1\n"
        "```\n"
        "### FILE: tpcc.py\n"
        "print('hi')\n"
    )
    parsed = parse_response(sample)
    assert set(parsed) == {"drivers/postgresdriver.py", "tpcc.py"}, parsed
    assert parsed["drivers/postgresdriver.py"] == "x = 1", parsed
    assert parsed["tpcc.py"] == "print('hi')", parsed


def test_safe_target():
    allowed = {"drivers/postgresdriver.py"}
    out = Path("/tmp/naive-llm-test-out")
    assert safe_target(out, "../evil.py", allowed) is None
    assert safe_target(out, "/etc/passwd", allowed) is None
    good = safe_target(out, "drivers/postgresdriver.py", allowed)
    assert good is not None and good.name == "postgresdriver.py"


def test_select_files():
    with tempfile.TemporaryDirectory() as tmp:
        d = _sample_output_dir(tmp)
        rewrite, context = select_files(d, "postgres")
        assert rewrite == ["drivers/postgresdriver.py", "tpcc.py"], rewrite
        assert context == ["tpcc.postgres.sql"], context


def test_default_prompt_unchanged():
    with tempfile.TemporaryDirectory() as tmp:
        d = _sample_output_dir(tmp)
        prompt = _build(d)
        assert TASK in prompt, prompt
        positions = [prompt.index(line) for line in RULES]
        assert positions == sorted(positions), (positions, prompt)
        assert "- Do not add new files or dependencies." in prompt
        assert prompt.count("### FILE:") == 1, prompt


def test_guidance_inserted_before_rules():
    guidance = "- Batch all per-row lookups into one set-based query.\n- Keep behavior identical."
    with tempfile.TemporaryDirectory() as tmp:
        d = _sample_output_dir(tmp)
        prompt = _build(d, guidance)
        task_end = prompt.index(TASK.splitlines()[-1])
        assert prompt.index(guidance) > task_end, prompt
        assert prompt.index(guidance) < prompt.index("Rules:"), prompt
        assert f"{guidance}\n\nRules:" in prompt, prompt
        assert prompt.count("### FILE:") == 1, prompt
        assert prompt.count("### FILE: <relative path>") == 1, prompt


def test_empty_guidance_like_none():
    with tempfile.TemporaryDirectory() as tmp:
        d = _sample_output_dir(tmp)
        plain = _build(d)
        assert _build(d, "") == plain
        assert _build(d, "   \n\t\n") == plain
        assert _build(d, None) == plain


def test_prompt_bank_files():
    files = sorted(PROMPTS_DIR.glob("*.txt"))
    assert files, f"no prompt files in {PROMPTS_DIR}"
    for path in files:
        text = path.read_text(encoding="utf-8")
        # selected-*.txt are search outputs and may legitimately be empty
        # (control wins); the hand-written bank must always have guidance.
        if not path.name.startswith("selected-"):
            assert text.strip(), path
            assert "- " in text, path
        assert "### FILE:" not in text, path
        assert "```" not in text, path


if __name__ == "__main__":
    test_parse_response()
    test_safe_target()
    test_select_files()
    test_default_prompt_unchanged()
    test_guidance_inserted_before_rules()
    test_empty_guidance_like_none()
    test_prompt_bank_files()
    print("ok")
