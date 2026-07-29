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


def opencode(mods, out: Path, constitution: str) -> None:
    """AGENTS.md constitution plus on-demand subagents in .opencode/agents/.

    opencode.json has an `instructions` field that accepts globs, which looks like the
    obvious home for modules. It is the wrong one: those files are loaded as instructions,
    so all 14 modules would be resident on every request - the exact cost this repository
    exists to avoid. Subagents are the only opencode mechanism selected per task from a
    description, so they are the honest analogue of a Claude Code skill.

    The trade-off is real and worth knowing: a subagent runs in its own context and reports
    back, rather than injecting knowledge into the conversation you are already in.

    opencode has no glob auto-attach for agents, so glob metadata is folded into the
    description - the only field the primary agent matches against.
    """
    write(out / "AGENTS.md", constitution)
    for m in mods:
        description = m["description"]
        if m["globs"]:
            description += " Applies to: " + ", ".join(m["globs"]) + "."
        lines = [
            "---",
            f"description: {description}",
            "mode: subagent",
            "---",
            "",
            m["body"],
        ]
        write(out / ".opencode" / "agents" / f"{m['name']}.md", "\n".join(lines))


def agent_skills(mods, out: Path, constitution: str) -> None:
    """The cross-client Agent Skills standard: .agents/skills/<name>/SKILL.md.

    Agent Skills is an open specification (agentskills.io) implemented by a large number
    of clients, so this single adapter covers tools that would otherwise need one adapter
    each - Codex, Gemini CLI, VS Code, Junie, Amp, goose, Roo Code and Zed among them.

    Selection works by progressive disclosure: clients load only name and description at
    startup, then read the body when a task matches the description. That is the same
    mechanism Claude Code skills use, which is why the module content needs no reshaping.

    The spec defines what goes inside a skill directory, not where those directories live.
    `.agents/skills/` is the convention clients scan for cross-client sharing, so that is
    what we emit; each client also scans its own native directory.

    Only `name` and `description` are emitted. The spec allows an arbitrary `metadata`
    map, but no client acts on a glob key there, so writing one would cost bytes and
    promise behaviour that does not exist. Globs are folded into the description instead -
    the description is the only field selection reads.
    """
    write(out / "AGENTS.md", constitution)
    for m in mods:
        description = m["description"]
        if m["globs"]:
            description += " Applies to: " + ", ".join(m["globs"]) + "."
        lines = [
            "---",
            f"name: {m['name']}",
            f"description: {description}",
            "---",
            "",
            m["body"],
        ]
        write(
            out / ".agents" / "skills" / m["name"] / "SKILL.md",
            "\n".join(lines),
        )


ADAPTERS = {
    "claude-code": claude_code,
    "cursor": cursor,
    "copilot": copilot,
    "windsurf": windsurf,
    "opencode": opencode,
    "agent-skills": agent_skills,
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
