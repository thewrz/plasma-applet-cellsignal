import pathlib
import subprocess
import sys


ROOT = pathlib.Path(__file__).parent.parent


def test_feeder_modules_import_directly_from_checkout():
    paths = (
        'feeders/mmcli/cellsignal-feeder-mmcli',
        'feeders/mmcli/mmcli_parse.py',
        'feeders/xmm7360/xmm7360_decode.py',
    )
    for path in paths:
        result = subprocess.run(
            [sys.executable, '-c', f'import runpy; runpy.run_path({path!r})'],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        assert result.returncode == 0, result.stderr
