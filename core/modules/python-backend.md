---
name: python-backend
description: Python backend idioms — sync vs async correctness (blocking the event loop), type hints and runtime validation with Pydantic, SQLAlchemy session and N+1 handling, dependency injection in FastAPI, exception design, context managers, and worker/process model. Use when writing, changing, or reviewing Python server code (FastAPI, Django, Flask), or when pyproject.toml / requirements.txt is present.
globs:
  - "**/*.py"
  - "**/pyproject.toml"
  - "**/requirements.txt"
alwaysApply: false
---

# Python Backend — Idioms & Conventions

Framework choice decides whether a handler may block, and that is the difference between
working code and a stalled event loop. Detect before writing one.

## Detect the framework and data layer

Read `pyproject.toml` / `requirements.txt` before writing a handler.

| Marker | Stack | Consequence |
|---|---|---|
| `fastapi` | FastAPI | ASGI; a `def` handler runs in a threadpool, an `async def` handler must never block |
| `django` | Django | Historically WSGI and sync; async views exist but the ORM is only partially async |
| `flask` | Flask | WSGI, sync per request; async support needs an ASGI bridge |
| `starlette` without FastAPI | Starlette | Raw ASGI — no automatic request validation |
| `celery`, `rq`, `dramatiq` | Task queue | Work leaves the request; failures become invisible without result inspection |
| `sqlalchemy` `2.x` | SQLAlchemy 2 | `select()` style; `AsyncSession` only with an async driver |
| `psycopg2` | Sync driver | **Blocking** — never inside `async def` |
| `psycopg` `3.x` / `asyncpg` | Async-capable driver | Required for a genuinely async data path |
| `pydantic` `2.x` | Pydantic 2 | Rust core; v1 validators and config differ and do not port directly |

Check `requires-python` too. Several idioms in this module (`list[str]`, `X | None`,
`asyncio.to_thread`) assume a version that supports them.

## Symptom → first thing to check

| Symptom | Check first |
|---|---|
| Throughput collapses under load, CPU near idle | A blocking call inside `async def` — sync driver, `requests`, `time.sleep`, file I/O |
| One slow endpoint freezes unrelated endpoints | Same cause: the event loop is shared, so one blocked coroutine stalls all of them |
| `RuntimeError: Event loop is closed` at shutdown | A client or pool created on one loop and used or closed on another |
| `RuntimeWarning: coroutine ... was never awaited` | A missing `await` — the call did nothing and returned a coroutine object |
| Query counts grow linearly with rows returned | ORM N+1 — lazy relationship access in a loop, no `selectinload` / `joinedload` |
| `DetachedInstanceError` | The object is used after its session closed — the session scope is narrower than the object's lifetime |
| Data mutates between calls with no assignment | A mutable default argument, evaluated once at definition |
| Works in a test, fails in production with stale data | A session or connection reused across requests instead of scoped per request |
| `MemoryError` or RSS climbing on large result sets | The whole query materialised — stream with `yield_per` or paginate |
| Type checker passes, runtime gets the wrong type | Hints are not enforced — nothing validated at the boundary |
| CPU-bound work does not scale with threads | The GIL — needs processes or a task queue, not a threadpool |
| `ImportError` only in the packaged build | An implicit namespace package or a module not declared in the package configuration |
| Background task silently never runs | The task was created but not retained, and got garbage collected mid-flight |

This is an entry point, not an answer. Confirm with a traceback, query logs, or a profile
before acting. Investigation method → `debugging`.

## Async correctness

The most damaging Python backend bug: a blocking call inside `async def`. It stalls the
entire event loop, so one slow query freezes every concurrent request.

```python
# Wrong — sync driver inside an async handler blocks the whole loop
@app.get("/users/{uid}")
async def get_user(uid: int):
    return requests.get(f"{API}/users/{uid}").json()     # blocking
    # also blocking: psycopg2, time.sleep, open(), heavy CPU work

# Right — async client all the way down
async def get_user(uid: int):
    async with httpx.AsyncClient() as client:
        return (await client.get(f"{API}/users/{uid}")).json()

# Or keep the handler sync and let the framework use a threadpool
def get_user(uid: int):
    return requests.get(f"{API}/users/{uid}").json()
```

- A partially-async stack is worse than a fully sync one: you pay the complexity and still
  block. Choose one and be consistent per service
- Unavoidable blocking work goes through `asyncio.to_thread()` or
  `run_in_executor` — never inline
- CPU-bound work is limited by the GIL; use `multiprocessing` or a task queue, not threads
- `asyncio.gather` for concurrency; pass `return_exceptions=True` only if you actually
  inspect each result

## Types and validation

- Type hints on every public signature. They are documentation the tooling can check —
  run `mypy` or `pyright` in CI or they silently rot
- **Hints are not enforced at runtime.** Validate at the boundary with Pydantic and let the
  model be the single source of truth:
  ```python
  class CreateUser(BaseModel):
      email: EmailStr
      age: int = Field(ge=0, le=130)
  ```
- Avoid `Any`; prefer `Protocol` for structural typing and `TypedDict` for dict shapes
- Never a mutable default argument:
  ```python
  def f(items: list[str] | None = None) -> None:
      items = items or []          # not  def f(items=[])
  ```
- Prefer `dataclass(frozen=True)` or Pydantic models over passing bare dicts between layers

## Exceptions

- Catch the specific exception. `except Exception:` at a low level hides real bugs, and a
  bare `except:` also swallows `KeyboardInterrupt` and `SystemExit`
- Never `except ...: pass` — if it is genuinely ignorable, log at debug and say why
- Preserve the chain: `raise ServiceError("load failed") from err`
- Define a domain exception hierarchy and translate to HTTP once, in a handler — not inside
  business logic
- `finally` or a context manager for cleanup; do not rely on the garbage collector

## Context managers and resources

```python
with open(path) as f:            # not f = open(path)
    data = f.read()

@contextmanager
def unit_of_work(session):
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
```

Use `pathlib.Path` for paths rather than string concatenation — it also avoids a class of
traversal bugs.

## SQLAlchemy / ORM

- **Session scope is per request**, never global and never module-level
- The N+1 problem is the default behaviour: lazy relationships fire one query per row. Use
  `selectinload` / `joinedload` deliberately
- Keep the transaction boundary in a service or unit-of-work, not scattered `commit()` calls
- Objects expire after commit — accessing an attribute afterwards triggers a fresh query, or
  raises if the session is closed
- Alembic migrations reviewed as code; see `db-operations` for lock-safe DDL

## Project and runtime

- `pyproject.toml` as the single source of project config; `ruff` for lint and format
- Virtual environment always; pin with a lockfile (uv, poetry, or `pip-tools`)
- Layout: keep application code in a package (`src/app/`), never scripts at the repo root
  that mutate `sys.path`
- Worker model matters: `uvicorn --workers N` forks processes, so module-level state is
  **not** shared between them. Anything shared belongs in Redis or the database
- Configuration from the environment via `pydantic-settings`, not module constants
- Structured logging with the stdlib `logging` module — never `print()` in a service

## Review checklist

- [ ] No blocking call inside `async def`; async stack consistent end to end
- [ ] Type hints present; `mypy`/`pyright` runs in CI
- [ ] Boundary input validated by a Pydantic model, not just annotated
- [ ] No bare `except:`, no `except Exception: pass`; causes preserved with `from`
- [ ] Resources acquired with a context manager
- [ ] No mutable default arguments
- [ ] ORM session per request; eager loading where relationships are traversed
- [ ] No shared mutable module state under a multi-worker server
- [ ] Config from environment; logging structured

## Related modules

- Cross-language service design → `backend-patterns`
- `pickle`, `yaml.load`, `shell=True` and other sinks → `security-audit`
- Migrations and production database work → `db-operations`
