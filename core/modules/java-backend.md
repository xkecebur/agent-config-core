---
name: java-backend
description: Java/Spring Boot stack context and conventions — paradigm detection (MVC vs WebFlux), persistence layer choice (JPA/R2DBC/JDBC/jOOQ/MyBatis), per-paradigm quality checklist, and Java coding standards. Use when writing, changing, or reviewing Java/JVM code, choosing a Spring API, discussing JVM backend architecture, or when a pom.xml / build.gradle is present.
globs:
  - "**/*.java"
  - "**/*.kt"
  - "**/pom.xml"
  - "**/build.gradle"
  - "**/build.gradle.kts"
alwaysApply: false
---

# Java Backend — Stack & Conventions

## Detect the stack first, never assume

The most common failure here is applying reactive idioms to a blocking codebase, or the
reverse. Check `pom.xml` / `build.gradle(.kts)` before choosing an API:

| Marker | Paradigm |
|---|---|
| `spring-boot-starter-webflux` | Reactive — `Mono`/`Flux`, `WebClient`, R2DBC |
| `spring-boot-starter-web` | Blocking MVC — `RestClient`/`RestTemplate`, JPA/JDBC |
| `spring-boot-starter-data-jpa` vs `-data-r2dbc` | Persistence layer |
| Java 21+ with virtual threads enabled | Blocking code is not a red flag |

Rules:
1. **Never mix paradigms** in one module (`.block()` inside WebFlux, `Mono` in an MVC controller).
2. **Fallback for greenfield projects**: Spring Boot 3.x + Web MVC + JPA + PostgreSQL, Java 21,
   Gradle. State this choice explicitly so it can be corrected.
3. Reactive is a deliberate choice, never a silent default.

## Quality checklist

**All Java projects:**
- [ ] No N+1 query pattern (JPA lazy loading, or a reactive chain issuing one call per item)
- [ ] No resource leak — use try-with-resources
- [ ] No magic numbers or hardcoded config that belongs in `application.yml`
- [ ] `@Transactional` boundary sits in the service layer, not the controller
- [ ] Errors handled explicitly — no empty catch, no `catch (Exception e)` that swallows

**Reactive (WebFlux):**
- [ ] No `.block()` or blocking I/O on the event loop
- [ ] Errors handled with `onErrorResume` / `onErrorMap` / `doOnError`, not try-catch around the chain
- [ ] Context propagation (security, tracing) survives across operators

**Blocking (MVC):**
- [ ] `@ControllerAdvice` handles exceptions; stack traces never reach the client
- [ ] Connection pool (HikariCP) sized deliberately, timeouts explicit
- [ ] Long blocking calls do not exhaust the thread pool — consider virtual threads on Java 21
- [ ] Lazy loading does not escape the transaction (`LazyInitializationException`)
- [ ] Entities are not used directly as request/response bodies — use DTOs

## Coding standards

- Constructor injection with final fields — not field injection, not manual instantiation
- Configuration in `application.yml` / environment variables, never hardcoded
- Interfaces for components likely to be swapped
- Validate input at the boundary with `@Valid` and Bean Validation constraints
- No non-null assumptions without `Optional` or an explicit null check

## Related modules

- Security audit, including the per-layer SQL injection sink matrix → `security-audit`
- Diff and quality review → `pr-review`
- Query and index tuning → `pg-review`
- Migrations and production database operations → `db-operations`
