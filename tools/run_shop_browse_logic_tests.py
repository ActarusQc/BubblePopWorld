"""Execute les tests ShopBrowseLogic hors Roblox.

Usage : python tools\\run_shop_browse_logic_tests.py
"""

import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HARNESS = ROOT / "tools" / "test_shop_browse_logic.lua"
BUNDLE = ROOT / "tools" / "_shop_browse_logic_bundle.lua"
LUAU = ROOT / "tools" / "luau" / "luau.exe"
SHARED = ROOT / "src" / "Shared"

MODULES = [
    "ShopBrowseLogic",
    "ShopBrowseLogicTests",
]

MARKER = "--@MODULES@"


def build_bundle() -> str:
    harness = HARNESS.read_text(encoding="utf-8")
    if MARKER not in harness:
        sys.exit(f"marqueur {MARKER} introuvable dans {HARNESS.name}")

    blocks = []
    for name in MODULES:
        path = SHARED / f"{name}.lua"
        if not path.is_file():
            sys.exit(f"module introuvable : {path}")
        source = path.read_text(encoding="utf-8")
        blocks.append(
            f"MODULE_LOADERS[{name!r}] = function()\n{source}\nend\n"
        )

    return harness.replace(MARKER, "\n".join(blocks))


def main() -> int:
    if not LUAU.is_file():
        sys.exit(f"interpreteur Luau introuvable : {LUAU}")
    BUNDLE.write_text(build_bundle(), encoding="utf-8")
    return subprocess.run([str(LUAU), str(BUNDLE)]).returncode


if __name__ == "__main__":
    sys.exit(main())
