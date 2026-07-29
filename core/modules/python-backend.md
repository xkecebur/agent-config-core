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
