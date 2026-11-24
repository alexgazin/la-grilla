#!/usr/bin/env python3
"""U30 · Every "⋯" menu keeps one order: Listen · Rename · Duplicate · Colour · … · Delete.

Menus are marked in Swift with `// U30 menu: <kind> …` and `// U30 end`. Inside, the standard
actions are recognised by the last part of their accessibility identifier (`.listen`, `.rename`,
`.duplicate`, `.color`, `.delete`) and the destructive action by `role: .destructive`. The audit
checks that the standard actions appear in that order, that there is exactly one destructive action
and that nothing but modifiers follows it, and that the menus of every kind exist.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ORDER = {"listen": 0, "rename": 1, "duplicate": 2, "color": 3, "delete": 9}
REQUIRED = {"track", "clip", "section", "pad", "version"}
IDENTIFIER = re.compile(r'accessibilityIdentifier\("([^"]+)"\)')
CONTROL = re.compile(r'^\s*(?:if\b.*\{\s*)?(Button|Picker|Menu|Toggle|NavigationLink)\s*[\(\{]|^\s*[a-zA-Z]+Menu\(')


def audit(path: pathlib.Path) -> tuple[list[str], set[str]]:
    problems, kinds = [], set()
    lines = path.read_text(encoding="utf-8").splitlines()
    index = 0
    while index < len(lines):
        start = re.search(r"//\s*U30 menu:\s*([a-z ]+?)\s*(?:—|-|$)", lines[index])
        if not start:
            index += 1
            continue
        kind = start.group(1).strip()
        kinds.add(kind.split()[0] if kind.split()[0] in REQUIRED else kind.split()[-1])
        end = next((i for i in range(index + 1, len(lines)) if "// U30 end" in lines[i]), None)
        where = f"{path.relative_to(ROOT)}:{index + 1} ({kind})"
        if end is None:
            problems.append(f"{where}: no `// U30 end`")
            break
        region = lines[index + 1:end]
        sequence, destructive, last_control = [], [], -1
        for offset, line in enumerate(region):
            if CONTROL.search(line):
                last_control = offset
            for identifier in IDENTIFIER.findall(line):
                action = identifier.rsplit(".", 1)[-1]
                if action in ORDER:
                    sequence.append((ORDER[action], action, offset))
            if re.search(r"role:\s*\.destructive", line):
                destructive.append(offset)
        ranks = [rank for rank, _, _ in sequence]
        if ranks != sorted(ranks):
            problems.append(f"{where}: order {[name for _, name, _ in sequence]} should follow listen · rename · duplicate · color · … · delete")
        if len(destructive) != 1:
            problems.append(f"{where}: {len(destructive)} destructive actions; exactly one, last and red")
        elif destructive[0] < last_control:
            problems.append(f"{where}: the destructive action is not last")
        index = end + 1
    return problems, kinds


def main() -> int:
    problems, kinds = [], set()
    for folder in ("Features", "App"):
        for path in sorted((ROOT / folder).glob("*.swift")):
            found, seen = audit(path)
            problems += found
            kinds |= seen
    missing = REQUIRED - kinds
    if missing:
        problems.append(f"menus without the U30 order: {', '.join(sorted(missing))}")
    if problems:
        print("Menu order audit failed:")
        for problem in problems:
            print("  " + problem)
        return 1
    print(f"Menu order audit passed: {', '.join(sorted(kinds))} keep Listen · Rename · Duplicate · Colour · … · Delete last")
    return 0


if __name__ == "__main__":
    sys.exit(main())
