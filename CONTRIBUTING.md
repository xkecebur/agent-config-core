# Contributing

## What is most useful

1. **Verifying an adapter.** The support matrix in the README marks Cursor, Copilot, and
   Windsurf as generated-but-unverified. Running one in a real editor and reporting what
   broke is the highest-value contribution here.
2. **A new adapter.** One function in `scripts/render.py`, registered in `ADAPTERS`.
3. **Sharpening a module.** Specific beats general — see the bar below.

## The bar for module content

A module earns its context cost only if it is specific enough to be wrong. Compare:

- Weak: "be careful with database migrations"
- Strong: "`ADD COLUMN NOT NULL` rewrites the table; use add-nullable → backfill →
  `ADD CONSTRAINT NOT VALID` → `VALIDATE`"

Prefer tables to prose. State the failure mode, not just the rule. If a claim is
version-dependent, say which version.

## Rules

- Never edit `dist/` — it is generated. Change `core/modules/` and rebuild.
- English only, in every file.
- Test hooks against a real case before submitting. A guard that silently does nothing is
  worse than no guard (see the gitleaks note in the README).
- No offensive-security tooling, target lists, or engagement material. This repo is for
  building and defending software.

## Workflow

```bash
./scripts/validate.sh       # frontmatter, build, and hook behaviour - must pass
shellcheck scripts/*.sh hooks/*.sh hooks/git/pre-commit
shfmt -d scripts/*.sh hooks/*.sh hooks/git/pre-commit
ruff check scripts/ && ruff format --check scripts/
```

CI runs exactly these. Running them locally first is faster than waiting for a red build.

Test fixtures that look like real credentials (used to prove the secret guards fire) are
allowlisted in `.gitleaksignore` by fingerprint. Never add a real finding there — rotate
the credential instead.
