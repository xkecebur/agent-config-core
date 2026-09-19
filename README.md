# Agent Config Core

**Backend and web engineering knowledge for AI coding agents — written once, generated for
every agent.**

Built for engineers whose work does not stop at application code: the same person writes the
service, tunes the query, reviews the Terraform, and gets paged when it breaks. The modules
follow that reality — five backend languages, database operations, infrastructure, CI/CD,
application security, and detection — plus the two frontend concerns that reach a backend
engineer anyway: the styling layer and measurable page quality.

Most agent-configuration repos are a pile of instructions for one tool. This one separates
*what you know* from *how a particular agent loads it*, so the same modules run on Claude
Code, Cursor, GitHub Copilot, Windsurf, opencode, and every client implementing the
[Agent Skills](https://agentskills.io) standard — and adding another target means writing
one adapter function, not rewriting the content. The constitution is also emitted as
`AGENTS.md`, which many other agents read with no adapter at all.

**Not** a general-purpose prompt collection. There is nothing here about mobile, data
science, or writing marketing copy. Frontend coverage is deliberately narrow: the styling
layer (`css-styling`) and measurable quality (`frontend-quality`). There are no
framework-specific frontend modules — no React, no Next.js, no component library — because
those are not written from daily use here, and a module that could not be wrong is not worth
the context it costs.

---

## The problem it solves

A global instruction file is read on **every single request** — including "rename this
variable". As you add domains, that file grows, and you pay for all of it all the time.
Worse, most agents cap how much rule/skill metadata they will load, so an oversized set
gets silently truncated: descriptions are cut, retrieval degrades, and the right module
stops being selected.

Measured on the setup this repo was extracted from:

| | Before | After |
|---|---|---|
| Constitution file | 215 lines | 126 lines |
| Module listing | 50,190 chars (~2× over budget, silently truncated) | 9,507 chars |

Same knowledge, more domains covered, 81% less always-on weight.

---

## Architecture

Three layers, chosen by *how deterministic the rule needs to be*:

| Layer | Contains | Loaded | Cost |
|---|---|---|---|
| **Constitution** (`AGENTS.md`) | Only what applies to every domain: response shape, severity scale, verification rules, destructive-action policy | Always | Keep it small |
| **Modules** (`core/modules/`) | Domain knowledge: checklists, tables, idioms | When relevant — by glob or by description match | Pay per use |
| **Hooks** (`hooks/`) | Things that must happen every time and cannot depend on the model remembering | Automatically | Free |

The layering rule is simple: **if it must always be true, it is a hook, not an
instruction.** A model can forget to run a secret scan. A pre-commit hook cannot.

---

## Modules

**Languages** — idioms and the failure modes specific to each runtime:

| Module | Covers |
|---|---|
| `java-backend` | Framework detection across Spring/Quarkus/Micronaut/Vert.x/Jakarta EE, paradigm detection, persistence choice, symptom table, per-paradigm checklist |
| `go-backend` | Router and data-layer detection, error wrapping and sentinels, context propagation, goroutine lifecycle, pool bounds, server timeouts, symptom table, table-driven tests |
| `node-backend` | Event-loop blocking, async correctness, unhandled rejections, TS strictness vs runtime validation, backpressure |
| `python-backend` | Blocking calls inside `async def`, Pydantic at the boundary, ORM session scope and N+1, GIL and worker model |
| `php-backend` | `strict_types` and type juggling, PHP 8 idioms (enums, readonly, `match`), PDO, Eloquent N+1, shared-nothing runtime |

**Cross-cutting** — the parts that outlive a language choice:

| Module | Covers |
|---|---|
| `backend-patterns` | Idempotency, timeout budgets, retry/backoff/jitter, circuit breakers, pagination, transactional outbox, cache stampede, error contracts, graceful shutdown |
| `api-contract` | Spec-first vs code-first, generated client types, RFC 9457 Problem Details, offset vs cursor pagination, idempotency keys, the breaking-change list, drift detection in CI |
| `auth-implementation` | Session vs JWT vs delegated IdP, cookie prefixes, OAuth `state`/PKCE/`nonce`/`redirect_uri`, refresh rotation with reuse detection, object-level authorisation, step-up |
| `debugging` | Evidence before hypothesis, bisecting by input/commit/layer, language-server investigation loop, falsifiable predictions, verification before claiming a fix |
| `db-operations` | Lock-safe DDL table, expand-contract migrations, bloat/autovacuum, replication, PITR, pooling |
| `pg-review` | Query plans, index strategy, schema review |
| `iac-review` | Terraform state security, pinning, the misconfigurations that become incidents |
| `devops-pipeline` | GitHub Actions script injection, `pull_request_target`, token scope, OIDC, supply chain |
| `security-audit` | JWT, per-layer injection sink matrix, dangerous sinks by language, container/K8s hardening, OWASP pass |
| `blue-team-detection` | Useful logging, detection engineering, attack-technique → detection-signal mapping, incident triage |
| `pr-review` | Review checklist per language |
| `lsp-tooling` | Language server setup, limitations, troubleshooting |

**Frontend** — the two concerns that reach a backend engineer anyway:

| Module | Covers |
|---|---|
| `css-styling` | Tailwind v3 vs v4 detection, CSS-first `@theme` configuration, the v3→v4 changes that fail silently, dynamic class names that never generate, `tailwind-merge` for class conflicts, cva variants, class-based dark mode, CSS-in-JS SSR traps |
| `frontend-quality` | Core Web Vitals thresholds and lab-vs-field data, a symptom table for LCP/INP/CLS, bundle budgets enforced in CI, WCAG 2.2 AA — keyboard reachability, overlay focus management, form labelling, contrast and target size |

Modules are opinionated on purpose. `db-operations` tells you *which* DDL statements rewrite
a table; `devops-pipeline` shows the exact `pull_request_target` shape that leaks secrets;
`node-backend` names `forEach(async …)` as always a bug. Generic advice is not worth the
context it consumes — if a module could not be wrong, it should not be there.

---

## Hooks

| Hook | Trigger | Behaviour |
|---|---|---|
| `format-file.sh` | After the agent writes a file | Formats by extension, returns lint output to the agent. Self-detecting: uninstalled tools are skipped, so it gains capability as you install more |
| `guard-secrets.sh` | Before a `git commit` command | Scans staged changes with gitleaks, blocks on a finding |
| `guard-destructive.sh` | Before any shell command | Asks for confirmation on `DROP TABLE`, `terraform destroy`, `kubectl delete`, force push, `dd`, and similar |
| `git/pre-commit` | git layer | Same secret guard, agent-independent — protects you even when a teammate uses a different assistant |

One field note worth repeating: `gitleaks protect --staged` was the documented way to scan
staged content, but **gitleaks v8.30 removed the `protect` subcommand**. It now exits 0
without scanning anything — a guard that looks healthy and protects nothing. These hooks
pipe the staged diff into `gitleaks stdin` instead. Test your guards with a real secret.

---

## Usage

```bash
git clone https://github.com/xkecebur/agent-config-core
cd agent-config-core

./scripts/build.sh                       # generate for every agent
./scripts/build.sh cursor                # or just one

./scripts/install.sh cursor ~/work/my-service
./scripts/validate.sh                    # frontmatter, build, and hook behaviour
```

Edit `core/modules/*.md` and rebuild. **Never edit `dist/`** — it is regenerated every build.

Hook installation per agent is documented in [docs/hooks.md](docs/hooks.md).

```
AGENTS.md              constitution - cross-domain rules only
core/modules/          14 modules - the single source of truth
hooks/                 3 agent-native hooks + git/pre-commit
scripts/build.sh       core -> dist/<agent>/
scripts/render.py      one function per agent
scripts/install.sh     copy a built adapter into a project
scripts/validate.sh    checks run locally and in CI
dist/                  generated, git-ignored, never edited by hand
```

### Adding an agent

Write one function in `scripts/render.py` that maps a parsed module to that agent's file
layout, and register it in `ADAPTERS`. The module content needs no changes.

---

## Support status

Two different things are worth separating, because they carry different confidence.

### Adapters — modules loaded selectively

An adapter maps every module into that agent's own on-demand loading mechanism. This is
where the context saving actually comes from. "Verified" means run in the real tool, not
assumed:

| Agent | Format | Selection mechanism | Hooks | Status |
|---|---|---|---|---|
| Claude Code | `skills/<name>/SKILL.md` + `CLAUDE.md` | description match | Native | **Verified** |
| Cursor | `.cursor/rules/*.mdc` | glob auto-attach | git-level only | Generated, not yet verified in-editor |
| GitHub Copilot | `.github/instructions/*.instructions.md` | `applyTo` path scope | git-level only | Generated, not yet verified in-editor |
| Windsurf | `.windsurf/rules/*.md` | trigger mode | git-level only | Generated, not yet verified in-editor |
| opencode | `.opencode/agents/*.md` + `AGENTS.md` | subagent description match | git-level only | Generated, not yet verified in-editor |
| **Agent Skills standard** | `.agents/skills/<name>/SKILL.md` + `AGENTS.md` | progressive disclosure on description | git-level only | Generated, not yet verified in a client |

Only Claude Code supports agent-native hooks today. For every other agent, install
`hooks/git/pre-commit` — it runs at the git layer and therefore works everywhere.

One adapter note worth stating, since it looks like a mistake otherwise: opencode's
`opencode.json` has an `instructions` field that accepts globs, which seems like the
natural home for modules. It is not — those files load as instructions, so all 14 would
sit in context on every request, which is the exact cost this repo exists to remove.
Subagents are opencode's only description-selected mechanism. The trade-off is that a
subagent answers from its own context rather than adding knowledge to the conversation
you are in.

The `agent-skills` row is worth reading twice: it is one adapter, but it is not one tool.
[Agent Skills](https://agentskills.io/specification) is an open specification — originally
built by Anthropic, released as a standard in December 2025 — and its client list runs to
several dozen products, including Codex, Gemini CLI, VS Code, Junie, Amp, goose, Roo Code,
and Zed. Each of those would otherwise have needed its own adapter.

It works the same way a Claude Code skill does, which is why the module content needed no
reshaping: clients read only `name` and `description` at startup, then load the body when
a task matches. The specification defines what lives inside a skill directory, not where
those directories go; `.agents/skills/` is the path clients scan for cross-client sharing.

Note that Cursor, GitHub Copilot, and opencode appear on that client list too. They keep
their own adapters here because their native mechanisms — glob auto-attach, `applyTo` path
scoping, subagent dispatch — are not the same as description matching, and which one
serves a given module better has not been tested. Use whichever you prefer.

### AGENTS.md — constitution only

`AGENTS.md` has become a cross-tool convention, and the constitution is emitted in that
format by four of the six adapters. Any agent reading it gets the cross-domain rules —
response shape, severity scale, verification discipline, destructive-action policy — with
**no adapter and no install step**, just the file at your repo root.

Per [agents.md](https://agents.md), that includes Aider, Warp, Devin, Jules, Kilo Code,
Factory, Semgrep, and others that have no Agent Skills support today, so the constitution
is all they can take. Modules need a selection mechanism, and those tools do not expose one
that maps onto per-artifact loading.

That list is the ecosystem's claim, not ours: it has not been tested here.

If you verify an adapter against a real editor, a PR correcting these tables is the single
most useful contribution.

---

## Maturity

Honest per-module status. "Daily use" means the content came out of real work; "newer" means
it is sound but has had less exposure. Treat the whole repo as **v0.1** and read a module
before adopting it.

| Status | Modules |
|---|---|
| Daily use | `java-backend`, `pg-review`, `pr-review`, `security-audit`, `lsp-tooling` |
| Newer, less exposure | `backend-patterns`, `debugging`, `go-backend`, `node-backend`, `python-backend`, `php-backend`, `db-operations`, `iac-review`, `devops-pipeline`, `blue-team-detection` |

The per-language modules were written to a consistent bar — each one names the failure mode
that specific runtime produces, not generic advice with the language's name attached. But
only `java-backend` and `go-backend` have an author who works in that stack daily. If you
write Node, Python, or PHP for a living and something reads as textbook rather than
experience, that is exactly the correction worth opening a PR for.

Two scope caveats worth stating plainly. Within `java-backend`, the Spring Boot content is
daily-use; the Quarkus, Micronaut, Vert.x, Helidon, and Ktor entries are researched rather
than lived, and are deliberately limited to detection markers and the failure modes those
frameworks are known for. And `debugging` codifies a method rather than a stack, so its
value depends on the language module it is paired with.

---

## Requirements

**Core** — needed to build and run anything here:

| Tool | Why |
|---|---|
| `bash` 4+ | Every script and hook |
| `python3` 3.9+ | `scripts/render.py` (standard library only, no pip install) |
| `jq` | Agent-native hooks parse their payload as JSON |
| `git` | The `pre-commit` guard |

**Optional** — each one unlocks more of the formatter hook. It is **self-detecting**: tools
that are absent are skipped silently, so nothing breaks if you install none of them.

| Tool | Adds |
|---|---|
| `gitleaks` | Secret guards (`guard-secrets.sh`, `pre-commit`) — the highest-value one |
| `shellcheck`, `shfmt` | Shell lint and formatting |
| `ruff` | Python lint and formatting |
| `hadolint` | Dockerfile lint |
| `gofmt` | Go formatting (ships with Go) |

### Install

**macOS / Linuxbrew**

```bash
brew install jq gitleaks shellcheck shfmt ruff hadolint
```

**Debian / Ubuntu**

```bash
sudo apt install jq shellcheck
# gitleaks: in Debian 13+ and Ubuntu 24.04+; older releases use the binary below
sudo apt install gitleaks
```

`shfmt`, `hadolint`, and `ruff` are not packaged for Debian/Ubuntu — see *Fallbacks* below.

**Fedora / RHEL**

```bash
sudo dnf install jq ShellCheck gitleaks hadolint    # note the capitalisation of ShellCheck
```

`shfmt` and `ruff` are not in the Fedora repositories — see *Fallbacks*.

**Arch**

```bash
sudo pacman -S jq shellcheck gitleaks shfmt ruff
```

`hadolint` is only in the AUR.

**Nix**

```bash
nix-shell -p jq gitleaks shellcheck shfmt hadolint ruff
```

**Windows**

The scripts are bash, so they need **Git Bash** (bundled with Git for Windows) or **WSL2**.
They will not run under PowerShell or `cmd`. WSL2 is the smoother path — use the
Debian/Ubuntu instructions inside it.

For native Git Bash:

```powershell
winget install jqlang.jq Git.Git
scoop install gitleaks shellcheck shfmt hadolint     # or: choco install ...
pip install ruff
```

Note that the agent-native hooks assume a POSIX shell. If your agent launches hooks through
PowerShell on Windows, use the git-level `pre-commit` guard instead — it runs wherever
`git commit` runs.

### Fallbacks when a package is missing

`ruff` — always available through Python packaging, on every OS:

```bash
pipx install ruff       # or: pip install ruff / uv tool install ruff
```

`shfmt` — via Go, or a release binary:

```bash
go install mvdan.cc/sh/v3/cmd/shfmt@latest
```

`gitleaks`, `hadolint`, `shfmt` — official static binaries, no package manager needed:

```bash
# example: gitleaks on linux x64, pinned to the version CI uses
VERSION=8.30.1
curl -sSfL -o /tmp/gitleaks.tar.gz \
  "https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/gitleaks_${VERSION}_linux_x64.tar.gz"
tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks
sudo install -m 0755 /tmp/gitleaks /usr/local/bin/gitleaks
```

Release pages: [gitleaks](https://github.com/gitleaks/gitleaks/releases),
[hadolint](https://github.com/hadolint/hadolint/releases),
[shfmt](https://github.com/mvdan/sh/releases).

### Verify

```bash
./scripts/validate.sh
```

Tools you have not installed are reported as `skip`, not as failures.

---

## Contributing

Contributions are welcome — especially **adapter verification**, which is the one thing that
turns a guess in the support matrix into a fact.

- [CONTRIBUTING.md](CONTRIBUTING.md) — what is useful, what will be declined, PR workflow,
  commit convention, review expectations
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — argue about the claim, not the person
- [SECURITY.md](SECURITY.md) — report a vulnerability privately, never in a public issue

## License

MIT — see [LICENSE](LICENSE).
