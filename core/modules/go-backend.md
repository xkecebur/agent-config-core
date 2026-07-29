---
name: go-backend
description: Go backend idioms and conventions — error wrapping and sentinel errors, context propagation, goroutine lifecycle and leak prevention, interface placement, zero values, HTTP server timeouts, graceful shutdown, and table-driven tests. Use when writing, changing, or reviewing Go code, designing a Go service, or when go.mod is present.
globs:
  - "**/*.go"
  - "**/go.mod"
alwaysApply: false
---

# Go Backend — Idioms & Conventions

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

## Related modules

- Cross-language service design → `backend-patterns`
- Injection sinks (`template.HTML`, `exec.Command`) → `security-audit`
