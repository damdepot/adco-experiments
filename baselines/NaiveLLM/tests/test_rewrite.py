import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.rewrite import parse_response, safe_target, select_files


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
        d = Path(tmp)
        (d / "drivers").mkdir()
        (d / "drivers" / "postgresdriver.py").write_text("x = 1\n")
        (d / "tpcc.py").write_text("print('hi')\n")
        (d / "tpcc.postgres.sql").write_text("CREATE TABLE t();\n")
        rewrite, context = select_files(d, "postgres")
        assert rewrite == ["drivers/postgresdriver.py", "tpcc.py"], rewrite
        assert context == ["tpcc.postgres.sql"], context


if __name__ == "__main__":
    test_parse_response()
    test_safe_target()
    test_select_files()
    print("ok")
