import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.query_codec import compile_queries, decompile_app
from src.rewrite import select_files


def test_compile_decompile_round_trip():
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "src"
        app = Path(tmp) / "app"
        out = Path(tmp) / "out"
        src.mkdir()
        (src / "query1.sql").write_text("select 1;\n")
        (src / "query2.sql").write_text("select 2;\n")
        (src / "schema.sql").write_text("create table t(x int);\n")

        compile_queries(str(src), str(app))
        driver = app / "db_app.py"
        assert driver.exists()
        assert "QUERY_1 =" in driver.read_text()
        assert "QUERY_2 =" in driver.read_text()
        assert (app / "schema.sql").exists()

        decompile_app(str(app), str(out))
        assert (out / "query1.sql").read_text().strip() == "select 1;"
        assert (out / "query2.sql").read_text().strip() == "select 2;"


def test_select_files_prefers_db_app():
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        (d / "db_app.py").write_text("x = 1\n")
        (d / "schema.sql").write_text("create table t();\n")
        rewrite, context = select_files(d, "postgres")
        assert rewrite == ["db_app.py"], rewrite
        assert context == ["schema.sql"], context


if __name__ == "__main__":
    test_compile_decompile_round_trip()
    test_select_files_prefers_db_app()
    print("ok")
