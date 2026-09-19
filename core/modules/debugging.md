---
name: debugging
description: Language-agnostic bug investigation method — evidence before hypothesis, narrowing the blast radius by input, commit, or layer, a language-server-driven investigation loop (diagnostics, definition, references, hover) instead of guessing, one change at a time, verification before claiming a fix, and the criteria for stopping and asking for data. Use when debugging a runtime error, exception, panic, crash, failing test, unexpected behaviour, an intermittent bug, or a regression after deploy. Pair with the language module for the stack-specific symptom table.
alwaysApply: false
---

# Debugging — Investigation Method

This module is about **how to investigate**, not about any one language's bugs. Load the
language module alongside it (`go-backend`, `java-backend`, `node-backend`,
`python-backend`, `php-backend`) for the stack-specific symptom table.

## Rule zero

**Do not guess and patch. Gather evidence until the cause is known, then change code.**

Changing something to see if it helps is not debugging — it is perturbing a system and
hoping. If a fix works but you cannot explain *why* the symptom disappeared, the bug is not
fixed; it moved or went quiet.

## The six steps

### 1. State the violated invariant

Before anything else, write one precise sentence: **what should happen, what actually
happens, at which boundary.**

- Weak: "the endpoint errors"
- Strong: "`POST /orders` with `qty=0` returns 500; it should return 400 from validation.
  The log shows the exception in the service layer, not the validator"

If that sentence cannot be written yet, information is missing. Go to step 2 and collect it
— do not jump to a fix.

### 2. Reproduce, and classify the determinism

| Behaviour | What it implies |
|---|---|
| Fails every time on the same input | Easiest case — bisection works directly |
| Fails sometimes | Suspect concurrency, ordering, caching, or shared state. Run it repeatedly, not once |
| Fails in one environment only | Compare configuration, dependency versions, and data — not code |
| Fails only after uptime | Suspect a leak (memory, connections, file descriptors, goroutines or threads) or growing data |
| Cannot reproduce at all | **Stop guessing.** Ask for logs, traces, a stack trace, or the exact conditions |

A non-deterministic bug is never declared fixed on the strength of one passing run.

### 3. Narrow the blast radius before reading code deeply

Three axes to bisect on — take the cheapest first:

- **Input** — shrink to the minimal case that still triggers it. Which field, removed, makes it pass?
- **Time or commit** — `git bisect`, or `git log -S<symbol>` / `git log -p <file>` for an
  obvious regression. Ask when it last worked.
- **Layer** — where is the last boundary at which the data is still correct? Handler →
  service → repository → database. One observation point in the middle halves the search space.

Bisecting by layer is almost always faster than reading the whole call path top-down.

### 4. Use the language server, not guesswork

Prefer language server queries over text search: `file:line` results, no false positives
from comments, strings, or similarly named symbols. Setup and limitations → `lsp-tooling`.

| Investigation question | Query |
|---|---|
| "Is anything already flagged in this file?" | diagnostics — **run this first**, it often answers outright |
| "Which function or type is this actually?" | go to definition — do not infer from the filename |
| "Who calls this? Is it even reached?" | find references — evidence of the execution path, and mandatory before changing a signature |
| "What is the real type here? Is it nullable?" | hover |
| "Which implementation runs at runtime?" | definition on the interface, then references on the implementations |

Text search still wins for string literals, configuration keys, error messages, and files no
language server covers.

**No references found does not mean unused.** Indexing may be incomplete (Java is slow on
large projects), the file may sit outside the project root, or the call may arrive through
reflection, dependency injection, generated code, or an HTTP route. Languages with no server
configured fall back to reading and grep — say so plainly rather than implying the same precision.

### 5. Hypothesis → prediction → test

A hypothesis worth testing makes a **falsifiable prediction**.

- Weak: "maybe something is wrong with the transaction"
- Strong: "if the cause is X, log line N will show value Y, and raising the timeout to 30s
  will make it pass"

Then test the prediction. **One change at a time** — change three things, see it improve, and
you have learned nothing while two stray edits ride along into the commit.

Temporary instrumentation is fine when it is marked for easy removal, removed before commit,
and never prints credentials, tokens, or PII. For logging and traces meant to survive — the
ones that make the *next* incident diagnosable — see `blue-team-detection`.

### 6. Verify, then widen

Before calling it done:

- [ ] The original reproduction now passes — **executed**, not assumed
- [ ] The cause states as one causal sentence, not "it stopped erroring"
- [ ] Non-deterministic bugs: run repeatedly, not once
- [ ] Relevant tests, build, and lint run; results reported as they are — if something
      fails, say it failed and show the output
- [ ] Temporary instrumentation removed
- [ ] Smallest change that fixes it; unrelated refactors go in a separate commit
- [ ] **The same pattern searched for elsewhere** — find references, or grep the shape. Bugs
      are rarely born alone
- [ ] Public contract changes (endpoint, schema, cross-module signature) name who is affected
      and the migration path

## Anti-patterns

| Pattern | Why it costs more than it saves |
|---|---|
| Shotgun debugging — change many things at once | Yields no information, and adds noise to the diff |
| Fixing the symptom instead of the cause | It returns wearing a different face, usually in production |
| Empty catch or recover to silence an error | Destroys the evidence; the next failure is undiagnosable |
| Deleting or skipping the failing test | The test is doing its job |
| Retry as a cure for a logic bug | Hides the cause and doubles the side effects when the operation is not idempotent |
| Blaming the library or compiler first | It is nearly always your own code. Suspect the library only with a minimal reproduction in hand |
| Claiming it is fixed without running anything | Not acceptable — verify first |
| Guessing an API name, path, or field to fit the hypothesis | Check the code. If it cannot be verified, state the assumption explicitly |

## When to stop and ask

Stop investigating and ask when:

- The bug will not reproduce and there are no logs, stack traces, or trace IDs
- It needs access you do not have (production logs, a dashboard, one user's data)
- Two or three strong hypotheses have died without narrowing anything — report what has been
  eliminated instead of quietly continuing to guess
- The fix requires a destructive or hard-to-undo action (mutating production data, dropping
  or altering a large table, force push)

When you stop, report what was tried, what has been **eliminated** (the most valuable part),
and exactly which data would unblock the next step.

## Related modules

- Language-specific symptom tables → `go-backend`, `java-backend`, `node-backend`, `python-backend`, `php-backend`
- Slow queries, `EXPLAIN`, indexing → `pg-review`
- Bloat, locks, replication lag, pool exhaustion → `db-operations`
- Failing pipelines, deploys, and rollback → `devops-pipeline`
- Designing logs, metrics, and traces so the next incident is diagnosable → `blue-team-detection`
- Language server setup, limitations, troubleshooting → `lsp-tooling`
- When the bug turns out to have a security impact → `security-audit`
