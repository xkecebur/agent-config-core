#!/usr/bin/env python3
"""Render neutral core modules into agent-specific configuration formats.

Every adapter is a pure function of the core. Nothing is hand-maintained per agent, so
the content cannot drift between targets.

Neutral module frontmatter:
    name:         module identifier
    description:  when to load this module (the retrieval signal)
    globs:        optional file patterns that should auto-attach the module
    alwaysApply:  load unconditionally (rare — costs context on every request)
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

FRONTMATTER = re.compile(r"^---\n(.*?)\n---\n(.*)$", re.DOTALL)


def parse(path: Path) -> dict:
    text = path.read_text()
    m = FRONTMATTER.match(text)
    if not m:
        raise SystemExit(f"{path}: missing frontmatter")
    meta_block, body = m.group(1), m.group(2)

    meta: dict = {"globs": [], "alwaysApply": False}
    key = None
    for line in meta_block.splitlines():
        if line.startswith("  - "):
            if key == "globs":
                meta["globs"].append(line[4:].strip().strip('"'))
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key, value = key.strip(), value.strip()
        if key == "alwaysApply":
            meta[key] = value.lower() == "true"
        elif key == "globs":
            meta["globs"] = []
        else:
            meta[key] = value
    meta["body"] = body.lstrip("\n")
    return meta


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


# --- adapters ---------------------------------------------------------------


def claude_code(mods, out: Path, constitution: str) -> None:
    """Skills live in skills/<name>/SKILL.md; the constitution is CLAUDE.md."""
    write(out / "CLAUDE.md", constitution)
    for m in mods:
        fm = f"---\nname: {m['name']}\ndescription: {m['description']}\n---\n\n{m['body']}"
        write(out / "skills" / m["name"] / "SKILL.md", fm)


def cursor(mods, out: Path, constitution: str) -> None:
    """Rules live in .cursor/rules/<name>.mdc with glob auto-attach."""
    write(out / "AGENTS.md", constitution)
    for m in mods:
        lines = ["---", f"description: {m['description']}"]
        if m["globs"]:
            lines.append("globs: " + ",".join(m["globs"]))
        lines.append(f"alwaysApply: {str(m['alwaysApply']).lower()}")
        lines += ["---", "", m["body"]]
        write(out / ".cursor" / "rules" / f"{m['name']}.mdc", "\n".join(lines))


def copilot(mods, out: Path, constitution: str) -> None:
    """Repository instructions plus path-scoped .instructions.md files."""
    write(out / ".github" / "copilot-instructions.md", constitution)
    for m in mods:
        apply_to = ",".join(m["globs"]) if m["globs"] else "**"
        header = f"---\napplyTo: '{apply_to}'\ndescription: {m['description']}\n---\n\n"
        write(
            out / ".github" / "instructions" / f"{m['name']}.instructions.md",
            header + m["body"],
        )


def windsurf(mods, out: Path, constitution: str) -> None:
    """Rules live in .windsurf/rules/<name>.md with a trigger mode."""
    write(out / ".windsurf" / "rules" / "00-constitution.md", constitution)
    for m in mods:
        if m["alwaysApply"]:
            trigger = "always_on"
        elif m["globs"]:
            trigger = "glob"
        else:
            trigger = "model_decision"
        lines = ["---", f"trigger: {trigger}", f"description: {m['description']}"]
        if m["globs"]:
            lines.append("globs: " + ",".join(m["globs"]))
        lines += ["---", "", m["body"]]
        write(out / ".windsurf" / "rules" / f"{m['name']}.md", "\n".join(lines))


ADAPTERS = {
    "claude-code": claude_code,
    "cursor": cursor,
    "copilot": copilot,
    "windsurf": windsurf,
}


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("usage: render.py <agent> <core-dir> <out-dir> <constitution>")
    agent, core, out, constitution = (
        sys.argv[1],
        Path(sys.argv[2]),
        Path(sys.argv[3]),
        Path(sys.argv[4]),
    )

    if agent not in ADAPTERS:
        raise SystemExit(f"unknown agent: {agent} (known: {', '.join(ADAPTERS)})")

    mods = sorted(
        (parse(p) for p in core.glob("*.md")), key=lambda m: str(m.get("name", ""))
    )
    if out.exists():
        shutil.rmtree(out)

    ADAPTERS[agent](mods, out, constitution.read_text())

    # Hooks are shared verbatim; only the wiring differs per agent.
    hooks_src = core.parent.parent / "hooks"
    if hooks_src.is_dir():
        shutil.copytree(hooks_src, out / "hooks")

    print(f"  {len(mods)} modules -> {out}")


if __name__ == "__main__":
    main()
