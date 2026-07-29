---
name: pr-review
description: Code review for quality, maintainability, and language idiom across Java, Go, Python, and PHP. Use when reviewing a pull request, analyzing a diff, or checking code quality before merge.
alwaysApply: false
---

# Code Review

## Navigate with LSP, not grep

For Java, Go, Python, and PHP the language server gives accurate `file:line` with far
fewer false positives:

- `findReferences` / `incomingCalls` before flagging something as dead code or safe to
  refactor — confirm there is genuinely no caller
- `goToDefinition` to trace a symbol's origin instead of guessing a path
- `documentSymbol` for a quick map of functions and classes when judging single
  responsibility and function size

## Clean code

- [ ] Names describe intent, for variables, functions, and classes alike
- [ ] One function, one responsibility
- [ ] No dead code, no commented-out blocks, no TODO without a tracking issue
- [ ] No magic numbers — use named constants

## Java

Determine the paradigm from the build file before judging: `spring-boot-starter-webflux`
means reactive, `spring-boot-starter-web` means blocking MVC. Applying the wrong checklist
produces noise. Details in `java-backend`.

- [ ] `@Transactional` boundary in the service layer, not the controller
- [ ] Paradigms not mixed within a module
- [ ] Centralized exception handling; stack traces do not reach the client

## Go

- [ ] Errors returned and handled, never discarded with `_`
- [ ] Context wrapped with `fmt.Errorf("...: %w", err)` so the chain survives
- [ ] `context.Context` passed through call paths that do I/O
- [ ] No goroutine leak — every spawned goroutine has a termination path

## Python

- [ ] Type hints on public signatures; no `Any` hiding a real type
- [ ] Specific `except` clauses — no bare `except:` and no `except Exception: pass`
- [ ] No mutable default arguments (`def f(x=[])`)
- [ ] Resources acquired with a context manager (`with`), not manual open/close
- [ ] No blocking I/O inside an `async def`
- [ ] `pathlib` for path manipulation instead of string concatenation

## PHP

- [ ] `declare(strict_types=1)` present in new files
- [ ] Comparisons use `===`/`!==`; `==` invites type juggling
- [ ] Errors signalled by typed exceptions, not an ambiguous `false`/`null` return
- [ ] No `@` error suppression
- [ ] Queries via prepared statements or a query builder, never string interpolation
- [ ] PSR-4 autoloading and consistent namespaces; no manual `require`

## Robustness

- [ ] Every error handled explicitly
- [ ] Input validated before reaching the service layer
- [ ] No non-null assumptions without a check

## Maintainability

- [ ] Configuration in environment variables or config files, not hardcoded
- [ ] Dependency injection rather than hardcoded instantiation
- [ ] No N+1 query pattern

## Output format

```
[CRITICAL] Description — file:line — impact — fix
[HIGH]     Description — file:line — impact — fix
[MEDIUM]   Description — file:line — impact — fix
[LOW]      Description — file:line — impact — fix
[DEBT]     Technical debt — record it, no fix required now (a tag, not a severity)
```
