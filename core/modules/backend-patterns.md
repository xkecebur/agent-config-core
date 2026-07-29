---
name: backend-patterns
description: Language-agnostic backend service design — idempotency, timeout budgets, retry with backoff and jitter, circuit breakers, pagination strategy, transactional outbox, cache invalidation and stampede, API versioning, error contracts, health checks, and graceful shutdown. Use when designing an endpoint or service, integrating an external dependency, debugging duplicate or lost writes, or reviewing resilience and API shape.
alwaysApply: false
---

# Backend Patterns — Language Agnostic

These decisions outlive any framework choice. Language-specific idioms live in
`java-backend`, `go-backend`, `node-backend`, `python-backend`, and `php-backend`.

## Idempotency

Any endpoint that creates or moves money, or that a client may retry, needs an idempotency
key. Networks fail *after* the server has committed — the client cannot tell a lost response
from a lost request.

- Client sends `Idempotency-Key: <uuid>`; the server stores key → result
- The key is stored **in the same transaction** as the effect, or the guarantee is fiction
- Replay returns the original response rather than doing the work again
- Include a request fingerprint so the same key with a different body is a client error
- Expire keys after a defined window (24h is common) and say so in the API docs

Without this, every retry, every double-click, and every queue redelivery is a duplicate.

## Timeouts, retries, and circuit breakers

**Every** outbound call needs an explicit timeout. A default of "infinite" is how one slow
dependency exhausts your thread or connection pool and takes the service down.

- **Timeout budget:** if the caller's budget is 3s, an inner call cannot be given 5s. Pass
  the remaining budget down (deadline propagation) instead of setting each timeout in isolation
- **Retry only idempotent operations.** Retrying a non-idempotent POST creates duplicates
- Exponential backoff **with jitter** — synchronized retries from many clients are a
  self-inflicted thundering herd
- Cap total attempts and total elapsed time, not just attempt count
- **Circuit breaker** for a dependency that is already failing: after N failures, fail fast
  for a cooldown, then probe with a single request. Retrying a service that is down turns a
  partial outage into a full one
- Never retry a 4xx. It will fail identically

## Pagination

| Strategy | Use when | Caveat |
|---|---|---|
| Offset/limit | Small, stable datasets; user needs page numbers | `OFFSET 100000` scans and discards 100k rows; items shift between pages as data changes |
| Cursor (keyset) | Large or live datasets, infinite scroll, sync | No random page access; cursor must be a stable, unique, ordered key |

Cursor pagination: `WHERE (created_at, id) < (:cursor_ts, :cursor_id) ORDER BY created_at DESC, id DESC LIMIT :n`.
Include the tiebreaker column or rows with identical timestamps are skipped or repeated.

Always enforce a maximum page size on the server. A client asking for `limit=1000000` must
not be able to ask the database for it.

## Transaction boundaries and the outbox

- One transaction per business operation, opened in the service layer, never in a controller
  or a repository method
- **Do not call external services inside a transaction.** A 30s HTTP call holds database
  locks for 30 seconds
- Dual-write problem: writing to the database and publishing an event are not atomic. If the
  publish fails after commit, the event is lost forever

**Transactional outbox** is the standard fix:
1. Write the business row and an `outbox` row in the same transaction
2. A separate relay reads the outbox and publishes
3. Mark published; consumers must be idempotent because at-least-once delivery is guaranteed,
   exactly-once is not

## Caching

- Name the invalidation strategy before adding the cache. "We will figure it out later" means
  stale data in production
- **Stampede**: when a hot key expires, every request goes to the origin simultaneously.
  Mitigate with a short lock, or by refreshing ahead of expiry
- Add jitter to TTLs so entries written together do not expire together
- Never cache authorization decisions keyed only by resource — include the subject, or one
  user's permissions get served to another
- Cache the expensive computation, not the whole response, when only part is expensive

## API contracts

- Version at the boundary (`/v1/`) from day one. Adding versioning later means changing
  every client
- Additive changes only within a version: new optional fields are fine, removing or
  retyping a field is not
- Consistent error shape across the service. RFC 9457 (`application/problem+json`) if you
  have no strong reason otherwise:
  ```json
  { "type": "https://example.com/errors/insufficient-funds",
    "title": "Insufficient funds", "status": 409,
    "detail": "Balance 20.00 is below the requested 50.00",
    "instance": "/accounts/123/withdrawals" }
  ```
- Error messages carry a correlation id so a user report maps to a log line
- Never leak internal detail (stack traces, SQL, hostnames) into a client-facing error

## Health checks and shutdown

- **Liveness** answers "should I be restarted" — keep it trivial, and never check
  dependencies. A database blip must not trigger a mass pod restart
- **Readiness** answers "can I serve traffic" — this one may check critical dependencies
- Graceful shutdown on SIGTERM: stop accepting new work, finish in-flight requests within a
  bounded grace period, close pools, then exit. Without it every deploy drops live requests
- The grace period must be shorter than the orchestrator's kill timeout, or you get
  SIGKILL mid-request

## Concurrency and consistency

- Optimistic locking (version column) for "last write wins" bugs — cheaper than pessimistic
  locking and it surfaces the conflict to the caller
- Read-after-write on a read replica returns stale data. Either read from the primary after a
  write, or make the client tolerate the lag deliberately
- Background jobs must be idempotent — queues redeliver, and a worker can die after doing the
  work but before acknowledging

## Design review checklist

- [ ] Mutating endpoints accept an idempotency key, stored with the effect
- [ ] Every outbound call has an explicit timeout; budget propagated
- [ ] Retries only on idempotent operations, with backoff and jitter
- [ ] Circuit breaker on dependencies that can fail
- [ ] Pagination strategy matches dataset size; server enforces a maximum page size
- [ ] No external calls inside a database transaction
- [ ] Events published through an outbox, consumers idempotent
- [ ] Cache invalidation defined; stampede considered
- [ ] API versioned; consistent error contract; no internal detail leaked
- [ ] Liveness does not check dependencies; graceful shutdown implemented
