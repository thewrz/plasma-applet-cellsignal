"""Test path setup shared by every feeder test.

Feeders import the shared band/quality helpers from ``cellsignal_bands``. At
runtime that module is installed alongside each feeder script (same directory,
which the scripts add to ``sys.path``); under test it lives in ``feeders/shared``,
so put that directory on the path once for the whole suite.
"""
import pathlib
import sys

_SHARED = pathlib.Path(__file__).parent.parent / 'feeders' / 'shared'
if str(_SHARED) not in sys.path:
    sys.path.insert(0, str(_SHARED))
