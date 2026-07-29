# Agent Config Core

**Backend engineering knowledge for AI coding agents — written once, generated for every
agent.**

Built for backend engineers whose work does not stop at application code: the same person
writes the service, tunes the query, reviews the Terraform, and gets paged when it breaks.
The modules follow that reality — five backend languages, database operations, infrastructure,
CI/CD, application security, and detection.

Most agent-configuration repos are a pile of instructions for one tool. This one separates
*what you know* from *how a particular agent loads it*, so the same modules run on Claude
Code, Cursor, GitHub Copilot, and Windsurf — and adding a fifth target means writing one
adapter function, not rewriting the content.

**Not** a general-purpose prompt collection. There is nothing here about frontend, mobile,
data science, or writing marketing copy.

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
| `java-backend` | Paradigm detection (MVC vs WebFlux), persistence choice, per-paradigm checklist |
| `go-backend` | Error wrapping and sentinels, context propagation, goroutine lifecycle, server timeouts, table-driven tests |
| `node-backend` | Event-loop blocking, async correctness, unhandled rejections, TS strictness vs runtime validation, backpressure |
| `python-backend` | Blocking calls inside `async def`, Pydantic at the boundary, ORM session scope and N+1, GIL and worker model |
| `php-backend` | `strict_types` and type juggling, PHP 8 idioms (enums, readonly, `match`), PDO, Eloquent N+1, shared-nothing runtime |

**Cross-cutting** — the parts that outlive a language choice:

| Module | Covers |
|---|---|
| `backend-patterns` | Idempotency, timeout budgets, retry/backoff/jitter, circuit breakers, pagination, transactional outbox, cache stampede, error contracts, graceful shutdown |
| `db-operations` | Lock-safe DDL table, expand-contract migrations, bloat/autovacuum, replication, PITR, pooling |
| `pg-review` | Query plans, index strategy, schema review |
| `iac-review` | Terraform state security, pinning, the misconfigurations that become incidents |
| `devops-pipeline` | GitHub Actions script injection, `pull_request_target`, token scope, OIDC, supply chain |
| `security-audit` | JWT, per-layer injection sink matrix, dangerous sinks by language, container/K8s hardening, OWASP pass |
| `blue-team-detection` | Useful logging, detection engineering, attack-technique → detection-signal mapping, incident triage |
| `pr-review` | Review checklist per language |
| `lsp-tooling` | Language server setup, limitations, troubleshooting |

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
git clone https://github.com/<your-account>/agent-config-core
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

Honest matrix — "verified" means actually run, not assumed:

| Agent | Format | Modules | Hooks | Status |
|---|---|---|---|---|
| Claude Code | `skills/<name>/SKILL.md` + `CLAUDE.md` | Yes | Native | **Verified** |
| Cursor | `.cursor/rules/*.mdc` | Yes | git-level only | Generated, not yet verified in-editor |
| GitHub Copilot | `.github/instructions/*.instructions.md` | Yes | git-level only | Generated, not yet verified in-editor |
| Windsurf | `.windsurf/rules/*.md` | Yes | git-level only | Generated, not yet verified in-editor |

Only Claude Code supports agent-native hooks today. For every other agent, install
`hooks/git/pre-commit` — it runs at the git layer and therefore works everywhere.

If you verify an adapter against a real editor, a PR correcting this table is the single
most useful contribution.

---

## Maturity

Honest per-module status. "Daily use" means the content came out of real work; "newer" means
it is sound but has had less exposure. Treat the whole repo as **v0.1** and read a module
before adopting it.

| Status | Modules |
|---|---|
| Daily use | `java-backend`, `pg-review`, `pr-review`, `security-audit`, `lsp-tooling` |
| Newer, less exposure | `backend-patterns`, `go-backend`, `node-backend`, `python-backend`, `php-backend`, `db-operations`, `iac-review`, `devops-pipeline`, `blue-team-detection` |

The per-language modules were written to a consistent bar — each one names the failure mode
that specific runtime produces, not generic advice with the language's name attached. But
only `java-backend` and `go-backend` have an author who works in that stack daily. If you
write Node, Python, or PHP for a living and something reads as textbook rather than
experience, that is exactly the correction worth opening a PR for.

---

## Requirements

`bash`, `python3`, `jq`. Optional, enabling more hook capability:

```bash
brew install ruff shellcheck hadolint shfmt gitleaks
```

---

## License

MIT — see [LICENSE](LICENSE).
