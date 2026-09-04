"""Run the Lua 5.1 stubs using an optional, isolated lupa installation.

Install if needed: python -m pip install --target bin/lua-test-runtime lupa==2.8
This is test-only; no Python/Lua runtime is included in either game package.
"""
from pathlib import Path
import os
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bin/lua-test-runtime'))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    raise SystemExit('Lua tests require lua51 from lupa; see tests/run_lua_tests.py installation note.')

os.chdir(ROOT)
for path in sorted((ROOT / 'tests').glob('test_*.lua')):
    print(f'Running {path.name}', flush=True)
    LuaRuntime().execute(path.read_text(encoding='utf-8'))

compiler = LuaRuntime().eval('function(code, name) local f,e=loadstring(code,name); if not f then error(e) end; return true end')
files = list((ROOT / 'game/dota_addons/overforged/scripts/vscripts').rglob('*.lua'))
for path in files:
    compiler(path.read_text(encoding='utf-8-sig'), str(path))
print(f'Lua stub suites and Lua 5.1 syntax checks for {len(files)} runtime files passed.')
