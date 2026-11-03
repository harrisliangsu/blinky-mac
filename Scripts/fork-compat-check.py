#!/usr/bin/env python3
"""Checks a merged tree for the failures that have turned a weekday upstream
sync red before the Mac build even started.

Heuristic on purpose. It does not compile Swift. It exits non-zero with a
path and a reason, so a person or the sync agent can fix the tree first.

`--fill-placeholders` copies keys that exist in English and are missing from
ja, ko, or zh-Hant, using the English line as a placeholder. zh-Hans is left
alone: that translation is written, not filled in.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
TESTS = ROOT / "Tests"
RESOURCES = SOURCES / "Pulse" / "Resources"

# Files a merge rewrites often enough that a dropped brace has failed CI.
HOT_FILES = [
    "Sources/Pulse/Usage/UsageStore.swift",
    "Sources/Pulse/Usage/UsageBatch.swift",
    "Sources/Pulse/Usage/ProviderUsage.swift",
    "Sources/Pulse/Usage/UsageProvider.swift",
    "Sources/Pulse/Usage/UsageRoute.swift",
    "Sources/Pulse/Usage/UsageSource.swift",
    "Sources/Pulse/Providers/ConnectionRemedy.swift",
    "Sources/Pulse/Panel/Robot/RobotColour.swift",
    "Sources/Pulse/Settings/SettingsView.swift",
    "Sources/Pulse/App/AppSettings.swift",
]

# Cases this fork has to keep when a switch is really on that type.
# A `default` or `@unknown default` covers a case the switch does not name.
# ConnectionRemedy has no case of its own for Qoder; `.readBrowser` is the
# remedy Qoder's session failures use, so a switch that lists remedies and
# drops it is the same kind of hole.
FORK_CASES = {
    "Provider": {"qoder", "kimiCode"},
    "UsageWindow.Kind": {"credits", "sharedCredits", "topUp"},
    "ConnectionRemedy": {"readBrowser"},
    "UsageRoute": {"webSession"},
    "Unavailability": {
        "qoderSessionMissing",
        "qoderSessionExpired",
        "qoderNoCredits",
        "kimiSignInRequired",
        "kimiLoginExpired",
    },
}

# Bindings a bad merge has already declared twice. Also any `async let` in
# UsageStore.swift: those fetches live in UsageBatch now, one case each.
WATCHED_BINDINGS = ("qoderUsage", "rawQoder")


def main() -> int:
    fill = "--fill-placeholders" in sys.argv
    problems: list[str] = []
    if fill:
        problems.extend(fill_placeholders())
    problems.extend(conflict_markers())
    problems.extend(brace_balance())
    problems.extend(duplicate_fetches())
    problems.extend(batch_covers_providers())
    problems.extend(exhaustiveness())
    if problems:
        print("Fork compatibility check failed:", file=sys.stderr)
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1
    if not fill:
        print("Fork compatibility checks passed.")
    return 0


def swift_files(root: pathlib.Path) -> list[pathlib.Path]:
    if not root.exists():
        return []
    return sorted(path for path in root.rglob("*.swift") if path.is_file())


def rel(path: pathlib.Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


# --- conflict markers -------------------------------------------------------

def conflict_markers() -> list[str]:
    found: list[str] = []
    pattern = re.compile(r"^(?:<{7}|={7}|>{7}|\|{7})")
    for root in (SOURCES, TESTS):
        for path in root.rglob("*") if root.exists() else []:
            if not path.is_file():
                continue
            if path.suffix not in {".swift", ".strings", ".py", ".sh", ".yml", ".md", ".json"}:
                continue
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except UnicodeError:
                continue
            for number, line in enumerate(lines, start=1):
                if pattern.match(line):
                    found.append(
                        f"{rel(path)}:{number}: conflict marker left in the tree ({line[:24]!r})"
                    )
    return found


# --- braces -----------------------------------------------------------------

def brace_balance() -> list[str]:
    found: list[str] = []
    for relative in HOT_FILES:
        path = ROOT / relative
        if not path.exists():
            found.append(f"{relative}: merge-hot file is missing; brace check could not run")
            continue
        text = path.read_text(encoding="utf-8")
        balance, line = brace_delta(text)
        if balance != 0:
            found.append(
                f"{relative}: braces do not balance ({balance:+d} at line {line}). "
                "A merge often drops one."
            )
    return found


def brace_delta(text: str) -> tuple[int, int]:
    """Net `{` minus `}` in code, ignoring comments and strings.

    Returns the running total and the line where it last changed. A finished
    file should come back as zero.
    """
    i = 0
    n = len(text)
    line = 1
    depth = 0
    last = 1
    while i < n:
        char = text[i]
        if char == "\n":
            line += 1
            i += 1
            continue
        if char == "/" and i + 1 < n and text[i + 1] == "/":
            i = text.find("\n", i)
            if i < 0:
                break
            continue
        if char == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            if end < 0:
                break
            line += text[i:end].count("\n")
            i = end + 2
            continue
        if text.startswith('"""', i):
            end = closing_multiline(text, i + 3)
            line += text[i:end].count("\n")
            i = end
            continue
        raw = raw_string_width(text, i)
        if raw:
            hashes, start = raw
            end = find_raw_end(text, start, hashes)
            line += text[i:end].count("\n")
            i = end
            continue
        if char == '"':
            end = closing_quote(text, i + 1)
            line += text[i:end].count("\n")
            i = end
            continue
        if char == "{":
            depth += 1
            last = line
        elif char == "}":
            depth -= 1
            last = line
        i += 1
    return depth, last


def raw_string_width(text: str, i: int) -> tuple[int, int] | None:
    if text[i] != "#":
        return None
    hashes = 0
    while i + hashes < len(text) and text[i + hashes] == "#":
        hashes += 1
    if i + hashes < len(text) and text[i + hashes] == '"':
        return hashes, i + hashes + 1
    return None


def find_raw_end(text: str, start: int, hashes: int) -> int:
    closer = '"' + ("#" * hashes)
    end = text.find(closer, start)
    if end < 0:
        return len(text)
    return end + len(closer)


def closing_multiline(text: str, start: int) -> int:
    end = text.find('"""', start)
    if end < 0:
        return len(text)
    return end + 3


def closing_quote(text: str, start: int) -> int:
    """Index just past the closing quote, with `\\(` interpolation skipped as code is not."""
    i = start
    n = len(text)
    while i < n:
        char = text[i]
        if char == "\\" and i + 1 < n:
            if text[i + 1] == "(":
                i = skip_interpolation(text, i + 2)
                continue
            i += 2
            continue
        if char == '"':
            return i + 1
        i += 1
    return n


def skip_interpolation(text: str, start: int) -> int:
    depth = 1
    i = start
    n = len(text)
    while i < n and depth:
        char = text[i]
        if char == "(":
            depth += 1
            i += 1
            continue
        if char == ")":
            depth -= 1
            i += 1
            continue
        if text.startswith('"""', i):
            i = closing_multiline(text, i + 3)
            continue
        raw = raw_string_width(text, i)
        if raw:
            hashes, begin = raw
            i = find_raw_end(text, begin, hashes)
            continue
        if char == '"':
            i = closing_quote(text, i + 1)
            continue
        i += 1
    return i


# --- duplicate fetches ------------------------------------------------------

ASYNC_LET = re.compile(r"\basync\s+let\s+([A-Za-z_][A-Za-z0-9_]*)")
LET_RAW = re.compile(r"\blet\s+(raw[A-Z][A-Za-z0-9_]*)\b")
TUPLE_RAW = re.compile(r"\blet\s+\(([^)]*)\)")
RAW_NAME = re.compile(r"\b(raw[A-Z][A-Za-z0-9_]*)\b")


def binding_names(text: str) -> list[str]:
    text = code_only(text)
    names = [match.group(1) for match in ASYNC_LET.finditer(text)]
    names.extend(match.group(1) for match in LET_RAW.finditer(text))
    for match in TUPLE_RAW.finditer(text):
        names.extend(RAW_NAME.findall(match.group(1)))
    return names


def code_only(text: str) -> str:
    """Comments and strings replaced with spaces, newlines kept."""
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        char = text[i]
        if char == "/" and i + 1 < n and text[i + 1] == "/":
            newline = text.find("\n", i)
            if newline < 0:
                out.append(" " * (n - i))
                break
            out.append(" " * (newline - i))
            i = newline
            continue
        if char == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            chunk = text[i:end]
            out.append("".join("\n" if c == "\n" else " " for c in chunk))
            i = end
            continue
        if text.startswith('"""', i):
            end = closing_multiline(text, i + 3)
            chunk = text[i:end]
            out.append("".join("\n" if c == "\n" else " " for c in chunk))
            i = end
            continue
        raw = raw_string_width(text, i)
        if raw:
            hashes, begin = raw
            end = find_raw_end(text, begin, hashes)
            chunk = text[i:end]
            out.append("".join("\n" if c == "\n" else " " for c in chunk))
            i = end
            continue
        if char == '"':
            end = closing_quote(text, i + 1)
            chunk = text[i:end]
            out.append("".join("\n" if c == "\n" else " " for c in chunk))
            i = end
            continue
        out.append(char)
        i += 1
    return "".join(out)


def duplicate_fetches() -> list[str]:
    found: list[str] = []
    per_name: dict[str, list[str]] = {}
    for path in swift_files(SOURCES):
        text = path.read_text(encoding="utf-8")
        counts: dict[str, int] = {}
        for name in binding_names(text):
            counts[name] = counts.get(name, 0) + 1
            per_name.setdefault(name, []).append(rel(path))
        for name, count in sorted(counts.items()):
            # `async let` twice in one file does not compile. Other `raw*`
            # names (`rawValueLength`) are ordinary locals and can repeat.
            watched = name in WATCHED_BINDINGS or name.endswith("Usage")
            if count > 1 and watched:
                found.append(
                    f"{rel(path)}: `{name}` is bound {count} times. "
                    "A merge that keeps both sides' fetch leaves this, and it "
                    "does not compile."
                )
        if path.name == "UsageStore.swift":
            names = sorted({match.group(1) for match in ASYNC_LET.finditer(code_only(text))})
            if names:
                found.append(
                    "Sources/Pulse/Usage/UsageStore.swift: `async let` "
                    f"bindings ({', '.join(names)}) belong in UsageBatch.read, "
                    "one case per provider. Pasting them back here is how a "
                    "sync ends up with two Qoder fetches."
                )
    for name in WATCHED_BINDINGS:
        places = per_name.get(name, [])
        # One file may mention the name in a comment. Count real bindings only
        # when more than one file recorded it, which the loops above did for
        # every match. A single file with one match is the healthy case.
        files = sorted(set(places))
        if len(places) > 1 and len(files) > 1:
            found.append(
                f"`{name}` is bound in {', '.join(files)}. "
                "Keep the fetch in UsageBatch only."
            )
    return found


def batch_covers_providers() -> list[str]:
    """`collect` starts one `load` per hand-written provider.

    Profiled providers are not each an `async let`: `profiledReadings` loops
    `wanted` and calls the profile's fetch. `.pulseExtension` has no primary
    account; extension programs are fetched in `UsageStore`. A hand-written
    provider missing from `load` compiles and is never fetched on a full pass.
    """
    provider_cases: set[str] = set()
    handwritten: set[str] = set()
    for path in swift_files(SOURCES):
        if path.name != "UsageProvider.swift":
            continue
        for name, cases, _line in enum_declarations(path.read_text(encoding="utf-8")):
            if name == "Provider":
                provider_cases = cases
            elif name == "HandWrittenProvider":
                handwritten = cases
    batch = SOURCES / "Pulse" / "Usage" / "UsageBatch.swift"
    if not provider_cases or not batch.exists():
        return ["UsageBatch.collect: could not find Provider cases or UsageBatch.swift."]
    text = code_only(batch.read_text(encoding="utf-8"))
    # A loop that asks `read` for each wanted provider covers the whole enum.
    if re.search(r"\bfor\s+provider\s+in\s+wanted\b", text) and re.search(
        r"\b(?:read|load)\s*\(\s*provider\s*\)", text
    ):
        return []
    loaded = set(re.findall(r"\b(?:load|read)\s*\(\s*\.([A-Za-z_][A-Za-z0-9_]*)", text))
    # No primary account. UsageStore fetches each extension program itself.
    required = (handwritten or provider_cases) - {"pulseExtension"}
    missing = sorted(required - loaded)
    problems: list[str] = []
    if missing:
        shown = ", ".join(f".{name}" for name in missing)
        problems.append(
            "Sources/Pulse/Usage/UsageBatch.swift: collect never loads "
            f"{shown}. Add `async let … = load(.{missing[0]})` and a case in "
            "`read`. A hand-written provider missing here compiles and is "
            "never fetched on a full pass."
        )
    profiled = provider_cases - handwritten if handwritten else set()
    profile_loop = bool(
        re.search(r"\bfor\s+provider\s+in\s+wanted\b", text)
        and re.search(r"\.fetch\s*\(", text)
    )
    if profiled and not profile_loop:
        uncovered = sorted(profiled - loaded)
        if uncovered:
            shown = ", ".join(f".{name}" for name in uncovered[:8])
            problems.append(
                "Sources/Pulse/Usage/UsageBatch.swift: profiled providers are "
                f"not fetched ({shown}{'…' if len(uncovered) > 8 else ''}). "
                "Loop `for provider in wanted` and call the profile fetch, "
                "or `load` each one."
            )
    return problems


# --- exhaustiveness ---------------------------------------------------------

class EnumShape:
    def __init__(self, name: str, cases: set[str]) -> None:
        self.name = name
        self.cases = cases


def exhaustiveness() -> list[str]:
    shapes = load_enums()
    found: list[str] = []
    for path in swift_files(SOURCES):
        text = path.read_text(encoding="utf-8")
        for switch in find_switches(text):
            if switch["default"]:
                continue
            labels = switch["cases"]
            if len(labels) < 2:
                continue
            best: EnumShape | None = None
            best_overlap: set[str] = set()
            for shape in shapes:
                overlap = labels & shape.cases
                if not looks_like(labels, overlap, shape):
                    continue
                if len(overlap) > len(best_overlap):
                    best = shape
                    best_overlap = overlap
            if best is None:
                continue
            missing = FORK_CASES.get(best.name, set()) - labels
            if not missing:
                continue
            shown = ", ".join(f".{name}" for name in sorted(missing))
            found.append(
                f"{rel(path)}:{switch['line']}: switch looks like {best.name} "
                f"and has no `default` or `@unknown default`, but is missing {shown}. "
                "Add the case, or a default that stays quiet, before CI compiles it."
            )
    return found


def looks_like(labels: set[str], overlap: set[str], shape: EnumShape) -> bool:
    if len(overlap) < 2 or overlap != labels:
        # A result expression can share a name with this enum (`rateLimited`
        # on an error switch). Only a switch whose case labels all belong
        # here is treated as a switch on it.
        share_of_enum = len(overlap) / max(len(shape.cases), 1)
        share_of_switch = len(overlap) / max(len(labels), 1)
        return share_of_switch >= 0.8 and share_of_enum >= 0.35 and len(overlap) >= 4
    # Every label is one of this enum's cases.
    if len(overlap) >= 4:
        return True
    # Week / month / five-hour and nothing else: the ribbon switch that
    # failed the 1.4.3 build, before `.topUp` / `.credits` existed in it.
    if shape.name == "UsageWindow.Kind" and len(overlap) >= 2:
        return True
    # It already names a fork case, so the other fork cases are this
    # switch's to mention too.
    if overlap & FORK_CASES.get(shape.name, set()):
        return True
    return False


def load_enums() -> list[EnumShape]:
    shapes: list[EnumShape] = []
    for path in swift_files(SOURCES):
        text = path.read_text(encoding="utf-8")
        for name, cases, line in enum_declarations(text):
            label = name
            if name == "Kind" and "fiveHour" in cases:
                label = "UsageWindow.Kind"
            elif name == "Kind":
                continue
            if label not in FORK_CASES and name not in FORK_CASES:
                continue
            if label not in FORK_CASES:
                continue
            shapes.append(EnumShape(label, cases))
            del line
    return shapes


ENUM_HEAD = re.compile(r"\benum\s+([A-Za-z_][A-Za-z0-9_]*)\b")


def enum_declarations(text: str) -> list[tuple[str, set[str], int]]:
    found: list[tuple[str, set[str], int]] = []
    # Walk code only, so an enum mentioned in a comment is not a declaration.
    for start, line in keyword_positions(text, "enum"):
        match = ENUM_HEAD.match(text, start)
        if not match:
            continue
        brace = text.find("{", match.end())
        if brace < 0:
            continue
        body, _end = balanced_body(text, brace)
        cases = set(re.findall(r"\bcase\s+([A-Za-z_][A-Za-z0-9_]*)", body))
        # `case a, b, c` — the regex above only takes the first of a group.
        for group in re.findall(r"\bcase\s+([^:\n{]+)", body):
            for part in group.split(","):
                part = part.strip()
                name = re.match(r"([A-Za-z_][A-Za-z0-9_]*)", part)
                if name:
                    cases.add(name.group(1))
        found.append((match.group(1), cases, line))
    return found


def find_switches(text: str) -> list[dict[str, object]]:
    found: list[dict[str, object]] = []
    for start, line in keyword_positions(text, "switch"):
        brace = text.find("{", start)
        if brace < 0:
            continue
        # Don't treat `switch` inside `switched` — keyword_positions uses a boundary.
        body, _end = balanced_body(text, brace)
        direct, has_default = direct_cases(body)
        found.append({"line": line, "cases": direct, "default": has_default})
    return found


def keyword_positions(text: str, word: str) -> list[tuple[int, int]]:
    """Index and 1-based line of `word` used as code, not inside a string or comment."""
    positions: list[tuple[int, int]] = []
    i = 0
    n = len(text)
    line = 1
    while i < n:
        char = text[i]
        if char == "\n":
            line += 1
            i += 1
            continue
        if char == "/" and i + 1 < n and text[i + 1] == "/":
            newline = text.find("\n", i)
            if newline < 0:
                break
            i = newline
            continue
        if char == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            if end < 0:
                break
            line += text[i:end].count("\n")
            i = end + 2
            continue
        if text.startswith('"""', i):
            end = closing_multiline(text, i + 3)
            line += text[i:end].count("\n")
            i = end
            continue
        raw = raw_string_width(text, i)
        if raw:
            hashes, begin = raw
            end = find_raw_end(text, begin, hashes)
            line += text[i:end].count("\n")
            i = end
            continue
        if char == '"':
            end = closing_quote(text, i + 1)
            line += text[i:end].count("\n")
            i = end
            continue
        if text.startswith(word, i) and boundary(text, i, i + len(word)):
            positions.append((i, line))
            i += len(word)
            continue
        i += 1
    return positions


def boundary(text: str, start: int, end: int) -> bool:
    before = text[start - 1] if start else " "
    after = text[end] if end < len(text) else " "
    return not (before.isalnum() or before == "_") and not (after.isalnum() or after == "_")


def balanced_body(text: str, open_brace: int) -> tuple[str, int]:
    """The text inside the braces that open at `open_brace`, and the index past the close."""
    depth = 0
    i = open_brace
    n = len(text)
    while i < n:
        char = text[i]
        if char == "/" and i + 1 < n and text[i + 1] == "/":
            newline = text.find("\n", i)
            if newline < 0:
                return text[open_brace + 1 :], n
            i = newline
            continue
        if char == "/" and i + 1 < n and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        if text.startswith('"""', i):
            i = closing_multiline(text, i + 3)
            continue
        raw = raw_string_width(text, i)
        if raw:
            hashes, begin = raw
            i = find_raw_end(text, begin, hashes)
            continue
        if char == '"':
            i = closing_quote(text, i + 1)
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace + 1 : i], i + 1
        i += 1
    return text[open_brace + 1 :], n


def direct_cases(body: str) -> tuple[set[str], bool]:
    """Case labels and whether a default covers the rest, at this switch only."""
    labels: set[str] = []
    has_default = False
    i = 0
    n = len(body)
    depth = 0
    while i < n:
        char = body[i]
        if char == "/" and i + 1 < n and body[i + 1] == "/":
            newline = body.find("\n", i)
            i = n if newline < 0 else newline
            continue
        if char == "/" and i + 1 < n and body[i + 1] == "*":
            end = body.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        if body.startswith('"""', i):
            i = closing_multiline(body, i + 3)
            continue
        raw = raw_string_width(body, i)
        if raw:
            hashes, begin = raw
            i = find_raw_end(body, begin, hashes)
            continue
        if char == '"':
            i = closing_quote(body, i + 1)
            continue
        if char == "{":
            depth += 1
            i += 1
            continue
        if char == "}":
            depth = max(0, depth - 1)
            i += 1
            continue
        if depth == 0 and body.startswith("case", i) and boundary(body, i, i + 4):
            colon = find_case_colon(body, i + 4)
            clause = body[i + 4 : colon]
            labels.extend(re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*)", clause))
            i = colon + 1
            continue
        if depth == 0 and body.startswith("@unknown", i):
            has_default = True
        if depth == 0 and body.startswith("default", i) and boundary(body, i, i + 7):
            has_default = True
        i += 1
    return set(labels), has_default


def find_case_colon(body: str, start: int) -> int:
    i = start
    n = len(body)
    depth = 0
    while i < n:
        char = body[i]
        if char == "/" and i + 1 < n and body[i + 1] == "/":
            newline = body.find("\n", i)
            i = n if newline < 0 else newline
            continue
        if char == "/" and i + 1 < n and body[i + 1] == "*":
            end = body.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        if body.startswith('"""', i):
            i = closing_multiline(body, i + 3)
            continue
        raw = raw_string_width(body, i)
        if raw:
            hashes, begin = raw
            i = find_raw_end(body, begin, hashes)
            continue
        if char == '"':
            i = closing_quote(body, i + 1)
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth = max(0, depth - 1)
        elif char == ":" and depth == 0:
            return i
        i += 1
    return n


# --- localization placeholders ----------------------------------------------

KEY_LINE = re.compile(r'^"((?:\\.|[^"\\])*)"\s*=')
PLACEHOLDER_LANGS = ("ja", "ko", "zh-Hant")


def fill_placeholders() -> list[str]:
    english = RESOURCES / "en.lproj" / "Localizable.strings"
    if not english.exists():
        return [f"{rel(english)}: English strings file is missing"]
    en_lines = english.read_text(encoding="utf-8").splitlines(keepends=True)
    en_keys: dict[str, str] = {}
    for line in en_lines:
        match = KEY_LINE.match(line.lstrip("\ufeff"))
        if match:
            en_keys[match.group(1)] = line if line.endswith("\n") else line + "\n"
    notes: list[str] = []
    for language in PLACEHOLDER_LANGS:
        path = RESOURCES / f"{language}.lproj" / "Localizable.strings"
        if not path.exists():
            notes.append(f"{rel(path)}: translation file is missing; nothing was filled")
            continue
        current = path.read_text(encoding="utf-8")
        present = set()
        for line in current.splitlines():
            match = KEY_LINE.match(line.lstrip("\ufeff"))
            if match:
                present.add(match.group(1))
        missing = [key for key in en_keys if key not in present]
        if not missing:
            print(f"{language}: no missing keys.")
            continue
        addition = ["\n", "/* English placeholders — translate these. */\n"]
        for key in missing:
            addition.append(en_keys[key])
        path.write_text(current + "".join(addition), encoding="utf-8")
        print(f"{language}: copied {len(missing)} English placeholder(s).")
    return notes


if __name__ == "__main__":
    sys.exit(main())
