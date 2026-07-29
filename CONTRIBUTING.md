# Contributing

Thanks for considering it. This document tells you what is worth your time, what will be
declined, and exactly how to get a change merged.

## What is most useful

Ranked, honestly:

1. **Verifying an adapter.** The README support matrix marks Cursor, Copilot, Windsurf, and
   opencode as generated-but-unverified. Running one in a real tool and reporting what happened —
   even "it worked exactly as described" — is the single most valuable contribution. Use the
   *Adapter verification report* issue template.
2. **A new adapter.** One function in `scripts/render.py`, registered in `ADAPTERS`. The
   module content needs no changes.
3. **Correcting a module.** Especially in `node-backend`, `python-backend`, and
   `php-backend` — those were written to a high bar but the maintainer does not work in
   those stacks daily. If something reads like a textbook rather than experience, say so.
4. **Sharpening a module.** Replacing a general statement with a specific failure mode.

## What will be declined

Saying this up front so nobody wastes an afternoon:

- **Offensive-security material** — exploit code, target lists, engagement notes, scanning
  tooling. This repo is for building and defending software. `blue-team-detection` exists
  because detection is defensive; there is no offensive counterpart here and there will not be.
- **Generic advice.** "Write clean code", "handle errors properly", "use meaningful names".
  If a module cannot be wrong, it does not earn the context it costs.
- **Frontend, mobile, or data-science modules.** Out of scope — see the README.
- **Edits to `dist/`.** It is generated output. Change `core/modules/` and rebuild.
- **Reformatting or restructuring** without a functional reason.
- **New dependencies** for the build. `scripts/render.py` is standard library only, and
  should stay that way.

## The bar for module content

A module earns its context cost only if it is specific enough to be wrong. Compare:

- Weak: "be careful with database migrations"
- Strong: "`ADD COLUMN NOT NULL` rewrites the table; use add-nullable → backfill →
  `ADD CONSTRAINT NOT VALID` → `VALIDATE`"

Guidelines:

- Prefer tables to prose
- State the failure mode, not just the rule
- If a claim is version-dependent, name the version (`gitleaks v8.30 removed …`)
- Frontmatter `description` must say **when to load** the module — it is the retrieval
  signal, and `scripts/validate.sh` enforces its shape and length

## How to submit a change

```bash
# 1. Fork, then clone your fork - <your-username> is your own GitHub account,
#    not xkecebur. Add the upstream remote so you can rebase on master later:
#      git remote add upstream https://github.com/xkecebur/agent-config-core
git clone https://github.com/<your-username>/agent-config-core
cd agent-config-core

# 2. Branch. Any descriptive name; these prefixes are conventional here:
#    module/  adapter/  hooks/  docs/  ci/
git switch -c module/node-backend-streams

# 3. Change core/modules/ (never dist/), then verify
./scripts/validate.sh
shellcheck scripts/*.sh hooks/*.sh hooks/git/pre-commit
shfmt -d scripts/*.sh hooks/*.sh hooks/git/pre-commit
ruff check scripts/ && ruff format --check scripts/

# 4. Commit and open a PR against master
```

CI runs exactly those four commands plus a secret scan. Running them locally is faster than
waiting for a red build.

### Commit messages

[Conventional Commits](https://www.conventionalcommits.org/), lowercase subject, no trailing
period:

```
feat(module): add streams backpressure section to node-backend
fix(hooks): scan staged diff via gitleaks stdin
docs(readme): cross-platform requirements
ci: run on master as well as main
```

Types in use: `feat`, `fix`, `docs`, `ci`, `refactor`, `chore`.

### Pull requests

- One logical change per PR. A module correction and a new adapter are two PRs
- Fill in the PR checklist — it mirrors what CI enforces
- If you changed an adapter, state which editor and version you tested against, and update
  the support matrix in the README
- If you changed a hook, describe the trigger you tested with. "It runs without error" is
  not a test; a guard that silently does nothing is worse than no guard

## Review

Maintained by one person alongside a full-time job. Expect a first response within about a
week. A PR that is quiet is not rejected — ping it.

Reviews focus on three things, in order: is the claim **correct**, is it **specific enough
to be useful**, and does it **belong in this repo**. Expect direct feedback on all three.
Disagreement is fine — if you have evidence the maintainer is wrong, show it; that is how a
factual claim gets fixed.

## Testing hooks

Hooks are shell scripts that receive JSON on stdin. Test them with a real trigger:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"terraform destroy"}}' \
  | hooks/guard-destructive.sh | jq -r '.hookSpecificOutput.permissionDecision'   # -> ask
```

`./scripts/validate.sh` runs the full set. See [docs/hooks.md](docs/hooks.md) for details.

Test fixtures that look like real credentials (used to prove the secret guards fire) are
allowlisted in `.gitleaksignore` by fingerprint. Those fingerprints include line numbers, so
editing the surrounding file invalidates them and turns CI red — regeneration steps are in a
comment at the top of that file. **Never add a real finding there. Rotate the credential.**

## Licensing

By contributing, you agree your work is licensed under the [MIT License](LICENSE), same as
the rest of the project. No CLA.

## Code of conduct

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Reporting a vulnerability

Do not open a public issue — see [SECURITY.md](SECURITY.md).
