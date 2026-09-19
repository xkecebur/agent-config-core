---
name: go-backend
description: Go backend idioms and conventions — router and data-layer detection (net/http, chi, gin, echo, fiber, gRPC; database/sql, pgx, sqlc, GORM), error wrapping and sentinel errors, context propagation, goroutine lifecycle and leak prevention, interface placement, zero values, HTTP server timeouts, graceful shutdown, table-driven tests, and a symptom-to-cause table. Use when writing, changing, or reviewing Go code, designing a Go service, when go.mod is present, or when debugging a Go runtime error — context deadline exceeded, nil pointer dereference, a non-nil error that should be nil, goroutine leak, data race, too many connections, a hanging HTTP client.
globs:
  - "**/*.go"
  - "**/go.mod"
alwaysApply: false
---

# Go Backend — Idioms & Conventions

## Detect the router and data layer

Read `go.mod` first. The choice changes which idioms apply — not every Go service is
`net/http`, and one of the popular options is not even built on it.

| `go.mod` marker | Consequence |
|---|---|
| no third-party router | `net/http`; Go 1.22+ `ServeMux` handles method + path patterns |
| `go-chi/chi` | Plain `http.Handler` — stdlib middleware composes unchanged |
| `gin-gonic/gin` | `*gin.Context`, not `http.Handler`; stdlib middleware needs `gin.WrapH` |
| `labstack/echo` | `echo.Context`; the validator must be registered or `c.Validate` silently does nothing |
| `gofiber/fiber` | Built on **fasthttp, not `net/http`** — stdlib middleware does not apply, and `*fiber.Ctx` must never outlive the handler because its buffers are reused |
| `google.golang.org/grpc` | Interceptors instead of middleware; deadlines propagate through context |
| `jackc/pgx` | Native driver; `pgxpool` rather than `database/sql` |
| `sqlc.yaml` | Queries generated from SQL — regenerate on schema change, verify in CI |
| `gorm.io/gorm` | ORM; generated SQL is hidden, inspect it on hot paths |

Greenfield fallback: `net/http` (or chi once routing is non-trivial), `pgx` + `sqlc`,
PostgreSQL, `cmd/` plus `internal/`. State the choice so it can be corrected.

## Symptom → first thing to check

| Symptom | Check first |
|---|---|
| `context deadline exceeded`, intermittent | Timeout too tight, or `ctx` reused for work that outlives the response |
| `context canceled` in background work | A goroutine kept `r.Context()` — it is cancelled the moment the response is written |
| `err != nil` is true after returning `nil` | Nil interface trap — a typed nil pointer assigned to `error` is not `nil` |
| Whole process dies on one bad request | No panic-recovery middleware |
| Memory and goroutine count climb forever | A goroutine with no stop condition; a channel with no reader |
| `WARNING: DATA RACE` | Shared state without a mutex or channel; loop variable captured (Go < 1.22) |
| `too many connections` on the database | `SetMaxOpenConns` never set — the default is unlimited |
| `prepared statement "lrupsc_..." does not exist` | pgx behind PgBouncer in transaction mode — disable statement caching |
| `sql: no rows in result set` reaching the client | `sql.ErrNoRows` not mapped to a domain error |
| GORM update silently skips fields | Struct updates omit zero values (`0`, `""`, `false`) — use a map or `Select` |
| Rows missing with no error | `rows.Err()` never checked after the `rows.Next()` loop |
| HTTP client hangs forever | `http.Client` used without `Timeout` |
| File descriptors exhausted | `resp.Body.Close()` missing, or `defer` inside a loop |
| Fields tearing between requests (fiber) | `*fiber.Ctx` stored or used after the handler returned |
| Error response written, handler chain continues (gin) | `c.Abort()` not called |
| gRPC call never returns | Client set no deadline |

This is an entry point, not an answer. Confirm with `go test -race`, `pprof`, a log line, or
`gopls` diagnostics before acting. Investigation method → `debugging`.

## Errors

Go has no exceptions, so error handling *is* the control flow. Getting it wrong is the
most common source of unreadable Go.

```go
// Wrong — context lost, caller cannot tell what failed
if err != nil {
    return err
}

// Right — wrapped with %w so errors.Is/As still work up the stack
if err != nil {
    return fmt.Errorf("fetch user %s: %w", id, err)
}
```

- Wrap with `%w` when the caller may want to inspect the cause; use `%v` when you are
  deliberately hiding it (crossing an API boundary)
- Message style: lowercase, no trailing punctuation, no "failed to" prefix — the chain
  already reads as `fetch user 42: query row: connection refused`
- Compare with `errors.Is`, extract with `errors.As`. Never compare error strings
- Declare **sentinel errors** for conditions callers branch on:
  ```go
  var ErrNotFound = errors.New("not found")
  ```
- Never discard an error with `_` unless you write why in a comment
- Panic only for programmer bugs that make continuing meaningless — never for expected
  failure, and never across a library boundary

## Context

- `context.Context` is the **first parameter**, always named `ctx`. Never store it in a struct
- Pass it through every call that does I/O; a function that ignores `ctx` cannot be cancelled
- Set a deadline at the entry point, not deep inside:
  ```go
  ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
  defer cancel()   // always defer cancel, even when the timeout fires first
  ```
- `context.Value` is for request-scoped metadata (trace id, auth subject) — not for passing
  dependencies

## Goroutines

Every goroutine needs an answer to: **who stops it, and how does the caller know it ended?**

```go
// Leak — nothing closes ch, this goroutine blocks forever
go func() { ch <- work() }()

// Controlled — cancellation and completion are both explicit
g, ctx := errgroup.WithContext(ctx)
g.Go(func() error { return worker(ctx) })
if err := g.Wait(); err != nil { ... }
```

- Do not start a goroutine in a library function without returning a way to stop it
- `sync.WaitGroup` for "wait for N to finish", `errgroup` when any of them can fail
- Mutex for protecting state, channels for transferring ownership. Choosing channels for
  everything produces slower and harder code
- Guard shared maps — concurrent map writes are a runtime crash, not a race you can ignore

## Types and API shape

- **Accept interfaces, return structs.** Define the interface where it is *consumed*, not
  next to the implementation
- Keep interfaces small; one or two methods is normal in Go
- Make the zero value useful (`bytes.Buffer`, `sync.Mutex`) so callers need no constructor
- A `nil` slice and an empty slice behave the same for `append`, `len`, `range` — do not
  write special cases. A `nil` map is readable but panics on write
- Return concrete errors, not `interface{}`; avoid `any` unless the boundary truly is dynamic
- Struct tags matter for JSON contracts — an exported field without a tag leaks the Go name

## HTTP servers

```go
srv := &http.Server{
    Addr:              ":8080",
    Handler:           mux,
    ReadHeaderTimeout: 5 * time.Second,   // without this, Slowloris keeps connections open
    ReadTimeout:       15 * time.Second,
    WriteTimeout:      30 * time.Second,
    IdleTimeout:       60 * time.Second,
}
```

- `http.ListenAndServe` with the default server has **no timeouts at all** — never ship it
- Always `defer resp.Body.Close()` and drain the body, or connections are not reused
- Reuse one `http.Client` with a configured `Transport`; creating one per request exhausts
  sockets
- Graceful shutdown on SIGTERM:
  ```go
  <-sigCh
  ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
  defer cancel()
  _ = srv.Shutdown(ctx)
  ```

## Data access

The default pool is the trap: `database/sql` opens **unlimited** connections, so the limit
is discovered on the PostgreSQL side during a traffic spike.

```go
db.SetMaxOpenConns(n)                    // align with max_connections / the PgBouncer pool
db.SetMaxIdleConns(n)
db.SetConnMaxLifetime(30 * time.Minute)  // required when a proxy or LB drops idle connections
```

- Always the `...Context` variants: `QueryContext`, `ExecContext`, `QueryRowContext`
- `defer rows.Close()` **and** check `rows.Err()` after the loop — a mid-iteration failure
  is otherwise silent data loss
- Map `sql.ErrNoRows` with `errors.Is` to a domain error; never let it reach the client
- `defer tx.Rollback()` immediately after `Begin` — rollback after a successful commit is a no-op
- Parameterised queries only. Dynamic identifiers (table or column names) are validated
  against an allowlist, never escaped by hand
- pgx behind PgBouncer in transaction mode: disable the prepared-statement cache, or every
  other query fails with a missing statement
- GORM: `AutoMigrate` is not a migration tool — use goose, golang-migrate, or atlas, and
  keep migrations reviewed like code

## Testing

- **Table-driven tests** are the default idiom:
  ```go
  tests := []struct {
      name string
      in   string
      want int
      wantErr error
  }{...}
  for _, tt := range tests {
      t.Run(tt.name, func(t *testing.T) { ... })
  }
  ```
- `t.Helper()` in assertion helpers so failures point at the caller
- `t.Cleanup()` instead of manual teardown
- Run with `-race` in CI — data races are invisible until they are an outage

## Review checklist

- [ ] Errors wrapped with context; no bare `return err` at a boundary that matters
- [ ] No `_` discarding an error without justification
- [ ] `ctx` first parameter, propagated through I/O, never stored in a struct
- [ ] Every goroutine has a defined stop condition
- [ ] HTTP server and client have explicit timeouts
- [ ] Response bodies closed and drained
- [ ] Interfaces defined at the consumer, kept small
- [ ] `defer` inside a loop reviewed — it runs at function exit, not iteration end
- [ ] Tests table-driven; CI runs `-race`
- [ ] Connection pool bounded — `SetMaxOpenConns` is set, not left at the default
- [ ] Panic-recovery middleware installed on every server
- [ ] Parameterised queries only; no `fmt.Sprintf` into SQL

## Related modules

- Bug investigation method, evidence discipline, language-server-driven navigation → `debugging`
- Cross-language service design → `backend-patterns`
- Injection sinks (`template.HTML`, `exec.Command`) → `security-audit`
- Query plans and index strategy → `pg-review`
- Migrations, pooling, and production database operations → `db-operations`
