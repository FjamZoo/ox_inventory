"""Run server regression tests with Lua 5.4 (no FiveM process required).

The narrow syntax adapter below translates Cfx optional access, compound assignment,
and hash literals. Game APIs, ox_lib, metadata generation and DB I/O are mocked by
server.lua. This tests the real inventory/shop/crafting functions, not FiveM itself.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def translate(source):
    source = re.sub(r"`([^`]+)`", r"joaat('\1')", source)
    source = re.sub(r"(?m)^(\s*)([\w.\[\]]+)\s*([+*/-])=\s*(.*)$", r"\1\2 = \2 \3 (\4)", source)
    while match := re.search(r"\?(?=[.\[])", source):
        end = match.start()
        start, depth = end - 1, 0
        while start >= 0:
            char = source[start]
            if char in ')]':
                depth += 1
            elif char in '([':
                if depth == 0:
                    break
                depth -= 1
            elif depth == 0 and not (char.isalnum() or char in '._'):
                break
            start -= 1
        start += 1
        source = source[:start] + '(' + source[start:end] + ' or {})' + source[end + 1:]
    return source


with tempfile.TemporaryDirectory(prefix='ox-grid-tests-') as directory:
    temp = Path(directory)
    for relative in ['modules/inventory/server.lua', 'modules/shops/server.lua',
                     'modules/crafting/server.lua', 'modules/items/shared.lua', 'server.lua', 'client.lua']:
        target = temp / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(translate((ROOT / relative).read_text(encoding='utf-8')), encoding='utf-8')
        subprocess.run(['luac', '-p', str(target)], check=True, cwd=ROOT)
    subprocess.run(['lua', 'tests/server.lua', str(temp)], check=True, cwd=ROOT)
