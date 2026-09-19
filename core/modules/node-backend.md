---
name: node-backend
description: Node.js and TypeScript backend idioms — async/await pitfalls, event loop blocking, error propagation and unhandled rejections, stream backpressure, TypeScript strictness and runtime validation, ESM/CJS interop, connection pooling, and graceful shutdown. Use when writing, changing, or reviewing Node/TypeScript server code (Express, Fastify, NestJS, Koa), or when package.json is present.
globs:
  - "**/*.ts"
  - "**/*.mts"
  - "**/*.js"
  - "**/*.mjs"
  - "**/package.json"
  - "**/tsconfig.json"
alwaysApply: false
---

# Node.js / TypeScript Backend — Idioms & Conventions

Express is the most common Node stack, not the only one, and the differences between them
change what correct code looks like. Detect before writing a handler.

## Detect the framework and data layer

Read `package.json` before writing a single route.

| Marker | Stack | Consequence |
|---|---|---|
| `express` `^5` | Express 5 | A rejected async handler **does** reach the error middleware |
| `express` `^4` | Express 4 | A rejected async handler does **not** — every one needs wrapping |
| `fastify` | Fastify | Schema-first; responses are serialised through JSON Schema |
| `@nestjs/core` | NestJS | DI and decorators, the closest Node idiom to Spring |
| `hono` | Hono | Web-standard `Request`/`Response`, runs on Node and on edge runtimes |
| `koa` | Koa | Middleware is a chained `async` stack; errors propagate through `await next()` |
| `@prisma/client` | Prisma | Client must be a singleton; pool sizing is per process |
| `drizzle-orm` | Drizzle | SQL-first, types derived from the schema |
| `pg`, `postgres`, `kysely` | Driver or query builder | Pool lifecycle is yours to manage |
| `zod`, `valibot` | Boundary validation | Confirm it runs server-side, not only on a form |

Also check `"type"` in `package.json` (`module` vs `commonjs`) and `engines.node`. A wrong
ESM/CJS assumption is the single most confusing class of import error in this ecosystem.

## Symptom → first thing to check

| Symptom | Check first |
|---|---|
| Process dies with no trace, exit code 1 | A rejected promise with no handler — since Node 15 `unhandledRejection` **terminates the process** |
| `ERR_HTTP_HEADERS_SENT` | The response is sent twice — a missing `return` after `res.json()`, or an error handler writing again |
| Every request slows at once, not just one | The event loop is blocked: a large loop, a huge `JSON.parse`, catastrophic backtracking, sync crypto, `readFileSync` |
| `EADDRINUSE` on restart | The old process is still alive — shutdown never closed the server and its keep-alive sockets |
| A request hangs with no response and no error | An `await` that never resolves, or a handler that never returns a response |
| Hangs only when calling another service | An HTTP client with no timeout — Node applies no default |
| Sporadic `ECONNRESET` / `socket hang up` | A keep-alive agent reusing a socket the upstream already closed, with no idempotent retry |
| RSS climbs and never falls | Listeners, timers, or intervals with no removal path; an unbounded cache; a closure pinning a large request |
| `MaxListenersExceededWarning` | A listener attached inside a request handler and never removed |
| Connection pool timeout under load | Pool smaller than concurrency, or connections leaked by a transaction that never closes on the error path |
| `too many connections` at PostgreSQL | Every replica or worker opens its own pool — pool size × replicas exceeds `max_connections` |
| Empty body or `413` | The body parser limit, or the parser mounted after the route |
| Large uploads exhaust memory | The file is buffered instead of streamed — backpressure ignored |
| Env var `undefined` in production, fine locally | Config read in a module that was bundled or tree-shaken, or `.env` never loaded in that environment |
| Logs vanish when the container is killed | Shutdown never flushed, or `process.exit()` was called directly |
| Stack traces do not point at the original source | Source maps not enabled (`--enable-source-maps`) |
| Amounts are wrong but nothing errors | Money held in a `number` — use integer minor units or a decimal type |

This is an entry point, not an answer. Confirm with evidence — `--cpu-prof`, a heap
snapshot, structured logs, language server diagnostics — before acting. Investigation
method → `debugging`.

## The event loop is single-threaded

Every synchronous millisecond blocks **every** in-flight request. This is the failure mode
that does not exist in Java or Go and catches people moving from those stacks.

```js
// Blocks the loop — all concurrent requests stall
const hash = crypto.pbkdf2Sync(pw, salt, 600000, 32, 'sha512');
const data = fs.readFileSync(path);
const parsed = JSON.parse(hugePayload);   // also blocking, and unbounded

// Non-blocking
const hash = await promisify(crypto.pbkdf2)(pw, salt, 600000, 32, 'sha512');
const data = await fs.promises.readFile(path);
```

- Any `*Sync` function in a request path is a defect
- CPU-bound work belongs in `worker_threads` or a separate service, never inline
- Big `JSON.parse`/`stringify` and large regex are blocking too — bound the payload size
- Watch for accidental sync work in loops: a 10 ms operation × 500 items is a 5 second stall

## Async correctness

```js
// Silent failure — the promise is never awaited, errors vanish
items.forEach(async (item) => { await save(item); });

// Sequential, correct
for (const item of items) { await save(item); }

// Concurrent, and failures are visible
await Promise.all(items.map(save));
```

- `forEach` with an async callback is always a bug
- `Promise.all` rejects on the first failure — use `Promise.allSettled` when partial success
  is acceptable, and inspect every result
- Always `await` or explicitly `.catch()` a promise. A floating promise becomes an
  unhandled rejection, which **terminates the process** on modern Node
- Do not mix callbacks and promises in the same layer; wrap legacy APIs with `promisify`
- `await` inside a loop is fine when you *want* sequential — say so in a comment, otherwise
  a reviewer will "fix" it into `Promise.all` and break ordering

## Errors

- Throw `Error` instances, never strings — a thrown string has no stack
- Preserve the cause: `throw new AppError('load user failed', { cause: err })`
- Extend `Error` for domain errors and set `name`; check with `instanceof`, not string matching
- One centralized error handler per framework (Express error middleware, Fastify
  `setErrorHandler`, Nest exception filter) — never scatter try/catch that only re-throws
- Async route handlers in Express 4 do **not** forward rejections automatically. Use a
  wrapper or Express 5
- Register process-level handlers to log and exit deliberately rather than die silently:
  ```js
  process.on('unhandledRejection', (e) => { logger.fatal(e); process.exit(1); });
  ```

## TypeScript

- `strict: true` in `tsconfig.json`. Without it, most of the type safety you are paying for
  is off. Also enable `noUncheckedIndexedAccess`
- **Types are erased at runtime.** An `as User` on a request body is a lie the compiler
  believes. Validate at the boundary with zod/valibot/typebox and infer the type from the
  schema — one source of truth:
  ```ts
  const CreateUser = z.object({ email: z.string().email(), age: z.number().int().min(0) });
  type CreateUser = z.infer<typeof CreateUser>;
  ```
- Ban `any`; prefer `unknown` and narrow. `as` is an escape hatch that needs justification
- Model absence explicitly (`T | null`) rather than relying on `undefined` sneaking through
- Discriminated unions instead of optional-field soup

## Streams and payloads

- Stream large responses rather than buffering — `res.json(bigArray)` holds it all in memory
- Respect backpressure: use `pipeline()` (which propagates errors and cleans up), not
  manual `.pipe()` chains
- Set body size limits explicitly; the default is generous enough to be a DoS vector

## Modules, dependencies, runtime

- Decide ESM or CJS per project and stay there — mixed interop is where mysterious
  `ERR_REQUIRE_ESM` failures come from
- `npm ci` in CI, never `npm install` — the lockfile is the contract
- Audit transitive dependencies; the Node ecosystem's depth is its main supply-chain risk
- Pin the Node version (`.nvmrc`, `engines`) so local and production agree

## Database and lifecycle

- One shared connection pool per process, created at startup — not per request
- Pool size × instance count must stay under the database connection limit
- Graceful shutdown on SIGTERM: stop accepting connections, finish in-flight requests,
  then close the pool:
  ```js
  process.on('SIGTERM', async () => {
    server.close(async () => { await pool.end(); process.exit(0); });
  });
  ```
- Without this, rolling deploys drop live requests

## Review checklist

- [ ] No `*Sync` calls or CPU-bound work in a request path
- [ ] No async callback passed to `forEach`
- [ ] Every promise awaited or explicitly caught
- [ ] Errors are `Error` instances with a preserved `cause`
- [ ] Centralized error handler; async handlers forward rejections
- [ ] `strict: true`; request bodies validated at runtime, not just typed
- [ ] Response and body sizes bounded; large payloads streamed
- [ ] Single pool created at startup; graceful shutdown implemented

## Related modules

- Cross-language service design → `backend-patterns`
- Prototype pollution and injection sinks → `security-audit`
