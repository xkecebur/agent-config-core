---
name: java-backend
description: JVM backend stack context and conventions across frameworks — Spring Boot, Quarkus, Micronaut, Vert.x, Helidon, Jakarta EE, Ktor. Framework and paradigm detection (blocking vs reactive vs coroutine vs virtual threads), persistence layer choice (JPA/R2DBC/JDBC/jOOQ/MyBatis/Panache/Exposed), symptom-to-cause table, quality checklist, and JVM coding standards. Use when writing, changing, or reviewing Java/Kotlin code, choosing a framework API, discussing JVM backend architecture, when a pom.xml / build.gradle is present, or when debugging a JVM runtime error — LazyInitializationException, @Transactional not applying, HikariPool timeout, a hanging WebFlux request, N+1 queries, NoSuchBeanDefinitionException.
globs:
  - "**/*.java"
  - "**/*.kt"
  - "**/pom.xml"
  - "**/build.gradle"
  - "**/build.gradle.kts"
alwaysApply: false
---

# JVM Backend — Stack & Conventions

Spring Boot is the most common JVM stack, not the only one. Detect before choosing an API.

## Detect the framework first, never assume Spring

Read `pom.xml` / `build.gradle(.kts)` before writing a single annotation.

| Dependency marker | Framework |
|---|---|
| `spring-boot-starter-*`, `org.springframework.*` | Spring Boot |
| `io.quarkus:*` | Quarkus |
| `io.micronaut:*` | Micronaut |
| `io.vertx:*` | Vert.x |
| `io.helidon:*` | Helidon (SE or MP) |
| `jakarta.*` with none of the above | Plain Jakarta EE on an app server |
| `io.ktor:*` | Ktor (Kotlin) |

**Paradigm is a separate axis from framework** — the same framework runs several:

| Paradigm | Marker | Consequence |
|---|---|---|
| Blocking | `spring-boot-starter-web`, JDBC/JPA | Thread per request |
| Reactive (Reactor) | `spring-boot-starter-webflux` | `Mono`/`Flux`, `WebClient`, R2DBC |
| Reactive (Mutiny) | Quarkus reactive | `Uni`/`Multi` — not Reactor, different operators |
| Coroutine | Kotlin `suspend`, Ktor | Structured concurrency, `Dispatchers.IO` for blocking |
| Virtual threads | Java 21+ with loom enabled | Blocking code is **not** a red flag |

Rules:

1. **Never mix paradigms in one module** — `.block()` on a reactive path, `Mono` in a
   blocking controller, `runBlocking` inside a coroutine scope. These are bugs, not style.
2. **Greenfield fallback**: Spring Boot 3.x + Web MVC + JPA + PostgreSQL, Java 21, Gradle.
   State the choice explicitly so it can be corrected.
3. Reactive is a deliberate choice, never a silent default.

Persistence follows the project, not preference: JPA/Hibernate, Spring Data R2DBC, JDBC,
jOOQ, MyBatis, Panache (Quarkus), Micronaut Data, Vert.x SQL Client, Exposed (Kotlin).

## Symptom → first thing to check

| Symptom | Check first |
|---|---|
| `LazyInitializationException` | Entity touched outside the transaction or after the session closed |
| `@Transactional` has no effect | Self-invocation from the same class, or a non-public method — the proxy is bypassed |
| Connections exhausted, requests queue then time out | Pool size vs thread count; Spring's `spring.jpa.open-in-view=true` (the default) holds a connection for the whole request |
| WebFlux endpoint hangs, throughput collapses | `.block()` or a blocking driver (JPA/JDBC) on the event loop |
| Quarkus `BlockingNotAllowedException` | Blocking call on a reactive endpoint — needs `@Blocking` |
| Security context or MDC empty further down | Context not propagated across threads or reactive operators |
| Bean not found despite the annotation | Micronaut resolves DI at **compile time** — the annotation processor is not wired in |
| Response time degrades as data grows | N+1 — lazy loading inside a loop, no `join fetch` |
| `javax.*` does not resolve | Jakarta EE 9+ renamed the namespace to `jakarta.*` |
| Config value null despite being set | Wrong profile, mismatched `@ConfigurationProperties` prefix, or the file is not on the path |
| Works on the JVM, fails as a native binary | Reflection or dynamic proxies without registration (`@RegisterForReflection`) |
| Vert.x handler hangs until timeout | A branch never calls `end()` / `complete()` |

This is an entry point, not an answer. Confirm with a stack trace, a log line, or language
server diagnostics before acting. Investigation method → `debugging`.

## Quality checklist

**All JVM projects:**
- [ ] No N+1 query pattern (ORM lazy loading, or a reactive chain issuing one call per item)
- [ ] Resources closed on every exit path, including error paths — try-with-resources, or `use` in Kotlin
- [ ] Transaction boundary sits in the service layer, not the controller or resource
- [ ] No magic numbers or hardcoded config that belongs in a config file
- [ ] Errors handled explicitly — no empty catch, no `catch (Exception e)` that swallows
- [ ] Persistence entities are not used as request/response bodies — use DTOs
- [ ] Input validated at the boundary with Bean Validation constraints
- [ ] Every cross-network call has an explicit timeout
- [ ] Connection pool sized deliberately, timeouts explicit (HikariCP, Agroal, or framework default)
- [ ] A global exception handler exists; stack traces never reach the client

**Reactive (Reactor or Mutiny):**
- [ ] No `.block()`, no blocking I/O on the event loop
- [ ] Errors handled with operators (`onErrorResume`, `onFailure().recoverWith`), not try-catch around the chain
- [ ] Context propagation (security, tracing, MDC) survives across operators

**Blocking:**
- [ ] Lazy loading does not escape the transaction (`LazyInitializationException`)
- [ ] Long blocking calls do not exhaust the thread pool — consider virtual threads on Java 21+

**Kotlin:**
- [ ] No `runBlocking` on a suspend path; `Dispatchers.IO` for blocking calls
- [ ] `!!` only where the invariant is stated; prefer non-nullable types
- [ ] Every `CoroutineScope` has a clear lifecycle — no `GlobalScope`

## Coding standards

- Constructor injection with `final` fields / `val` — not field injection, not manual instantiation
- Configuration in config files or environment variables, never hardcoded
- Interfaces for components likely to be swapped
- No non-null assumptions without `Optional`, a non-nullable type, or an explicit null check
- Tests: JUnit 5, AssertJ, Mockito, Testcontainers — or the framework equivalent
  (`@QuarkusTest`, `@MicronautTest`)

## Related modules

- Bug investigation method, evidence discipline, language-server-driven navigation → `debugging`
- Security audit, including the per-layer SQL injection sink matrix → `security-audit`
- Diff and quality review → `pr-review`
- Query and index tuning → `pg-review`
- Migrations and production database operations → `db-operations`
