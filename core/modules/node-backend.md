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
