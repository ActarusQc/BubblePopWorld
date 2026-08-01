"""Assemble et exécute OnboardingConfigTests hors Roblox."""

import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HARNESS = ROOT / "tools" / "test_onboarding.lua"
BUNDLE = ROOT / "tools" / "_onboarding_bundle.lua"
LUAU = ROOT / "tools" / "luau" / "luau.exe"

MODULES = [
    ("OnboardingConfig", ROOT / "src" / "Shared" / "OnboardingConfig.lua"),
    ("OnboardingConfigTests", ROOT / "src" / "Shared" / "OnboardingConfigTests.lua"),
]
MARKER = "--@MODULES@"


def build_bundle() -> str:
    harness = HARNESS.read_text(encoding="utf-8")
    if MARKER not in harness:
        sys.exit(f"marqueur {MARKER} introuvable")

    blocks = []
    for name, path in MODULES:
        if not path.is_file():
            sys.exit(f"module introuvable : {path}")
        blocks.append(
            f"MODULE_LOADERS[{name!r}] = function()\n"
            f"script = {{ Parent = moduleProxy, Name = {name!r} }}\n"
            f"{path.read_text(encoding='utf-8')}\nend\n"
        )
    return harness.replace(MARKER, "\n".join(blocks))


def main() -> int:
    if not LUAU.is_file():
        sys.exit(f"interpréteur Luau introuvable : {LUAU}")
    BUNDLE.write_text(build_bundle(), encoding="utf-8")
    return subprocess.run([str(LUAU), str(BUNDLE)]).returncode


if __name__ == "__main__":
    sys.exit(main())
