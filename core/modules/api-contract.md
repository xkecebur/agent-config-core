---
name: api-contract
description: REST API contract design and drift prevention — spec-first vs code-first with OpenAPI, generated client types instead of hand-written ones, RFC 9457 Problem Details error shape, offset vs cursor pagination, idempotency keys and safe retries, versioning and the breaking-change list, and contract drift detection in CI. Use when designing a new REST endpoint, agreeing a contract between a service and its clients, changing a response shape that clients already consume, choosing a pagination model, defining an error format, or when client types and server responses have stopped matching.
globs:
  - "**/openapi.yaml"
  - "**/openapi.yml"
  - "**/openapi.json"
  - "**/swagger.yaml"
  - "**/swagger.json"
alwaysApply: false
---

# REST API Contracts — Design & Synchronisation

The core problem in one sentence: **hand-written client types lie.** The server changes,
the client's type checker stays green, and the wrong shape reaches runtime anyway. Every
rule below exists to keep one side from silently diverging from the other.

This module covers REST. A single-language codebase that shares types directly across the
boundary does not have this problem and does not need this module.

## Pick the direction of truth first

| Situation | Approach | Consequence |
|---|---|---|
| Several teams or clients, contract agreed before implementation | **Spec-first**: write OpenAPI, generate both sides | The contract becomes a reviewable artifact; requires discipline |
| One team, server moves fast, clients follow | **Code-first**: annotations in server code emit OpenAPI | Fast, but the spec follows whatever happened to be written |
| Third-party API with no spec | Write a spec from observation, **parse at the boundary** | Treat responses as untrusted until validated |

Whichever is chosen, the rule is the same: **one source of truth, and client types are
generated from it — never hand-written.**

Generated files are never edited by hand. An edit survives exactly until the next
generation run, which makes it a bug with a delayed fuse. Run codegen **in CI and fail the
build when the output differs from what is committed** — that diff is the contract and the
code having drifted apart, caught before release rather than in production.

## Error shape — RFC 9457 Problem Details

One error shape for the whole API. Without it every client screen invents its own error
handling and none of them agree.

```json
{
  "type": "https://api.example.com/errors/insufficient-balance",
  "title": "Insufficient balance",
  "status": 422,
  "detail": "Balance 15000 is below the requested amount 20000",
  "instance": "/transactions/9f2c",
  "traceId": "01JC8Z...",
  "errors": [{ "field": "amount", "code": "gt_balance" }]
}
```

- `type` is the **stable, machine-branchable error code**. Never make a client match on
  `title` or `detail` — both are for humans and are free to change
- Per-field validation failures go in a structured array, not concatenated into one sentence
- `traceId` ties the response to the server logs. This is the join point with
  `blue-team-detection`, and it is the difference between a debuggable incident and a guess
- `detail` never carries a stack trace, a SQL query, or PII — enforced in `security-audit`
- Status codes carry their actual meaning: `401` not authenticated, `403` authenticated but
  not permitted, `404` to hide cross-tenant existence, `409` state conflict, `422` business
  rule violation, `429` rate limited

## Pagination

| Model | When | Weakness |
|---|---|---|
| **Offset/limit** | Small datasets, jumping to page N is a requirement | Items shift as data changes (duplicates and skips); large `OFFSET` is slow in PostgreSQL |
| **Cursor (keyset)** | Feeds, large tables, frequently changing data | Cannot jump to an arbitrary page |

For a large table, cursor is almost always the answer. The cursor key must be **unique and
ordered** — `created_at` alone is not enough when timestamps collide, so pair it with the
primary key. Treat the cursor as opaque to the client and do not leak database internals
inside it. Query cost and index choice → `pg-review`.

Always enforce a server-side maximum on `limit`. `?limit=100000` is a denial of service the
client sends on your behalf.

## Idempotency and retries

Clients will repeat requests — the network drops, a button is double-clicked, a retry layer
fires. `GET`, `PUT`, and `DELETE` are idempotent by design. `POST` is not.

For a `POST` that moves money or creates important state: accept an `Idempotency-Key`
header, store key → result, and return the stored result for a key already seen. Without
it, a double submit is a double transaction. Retry, backoff, and timeout budgets on the
calling side → `backend-patterns`.

## Versioning and breaking changes

**Safe (additive):** adding an optional response field, adding an endpoint, adding an enum
value *when clients are known to tolerate unknown values*.

**Breaking:** removing or renaming a field, changing a type, tightening validation, changing
a status code, changing what a value means, making an optional field required.

A change to a public contract states who is affected and what the migration path is. In
practice: a path version (`/v2/...`) for a large change, or run old and new side by side
with a deprecation date. A field due for removal is marked `deprecated` in the spec first —
it does not simply disappear.

## Keeping the contract honest

- Keep the OpenAPI file **in the repository and review its diffs** like code
- Diff the spec in CI: fail the build on a breaking change without a version bump
- Consumer-side contract tests use the examples from the spec, so a server change is caught
  before it ships
- **Still parse responses at the boundary** on critical paths. A generated type is a promise
  about the contract, not a runtime guarantee about the bytes that arrived

## New endpoint checklist

- [ ] Defined in the spec, not only in code
- [ ] Client types generated, not hand-written
- [ ] Errors use the Problem Details shape with a stable `type`
- [ ] Pagination has a server-enforced `limit` ceiling
- [ ] State-changing `POST` accepts `Idempotency-Key`
- [ ] Object-level authorisation, not just a role check → `auth-implementation`
- [ ] No sensitive field serialised by accident — responses map from a DTO, never straight
      from a database entity
- [ ] For a change to an existing endpoint: affected callers and migration path written down

## Related modules

`backend-patterns` for retries, timeouts, and idempotency mechanics · `auth-implementation`
for authorising the endpoint · `pg-review` for pagination query cost · `security-audit` for
what must never appear in a response · `blue-team-detection` for correlation ids
