---
name: security-audit
description: Security audit for application code (Java, Go, Python, PHP) plus Dockerfiles and Kubernetes manifests — authentication and JWT, input validation with a per-layer injection sink matrix, sensitive data exposure, container and cluster hardening, and an OWASP Top 10 pass. Use when reviewing security, checking JWT or authentication logic, validating input handling, or hardening containers and Kubernetes workloads.
globs:
  - "**/Dockerfile*"
  - "**/k8s/**"
  - "**/kubernetes/**"
  - "**/*.java"
  - "**/*.go"
  - "**/*.py"
  - "**/*.php"
alwaysApply: false
---

# Security Audit

## Tracing with LSP rather than grep

Follow the real call flow instead of guessing from text matches:

- `findReferences` / `incomingCalls` on sensitive methods (authorization checks, query-by-id)
  to find paths that skip authorization — broken access control and IDOR
- `goToDefinition` to verify a query binding is genuinely parameterized all the way down
  (JPA/JPQL, R2DBC, JDBC, jOOQ, MyBatis)
- `outgoingCalls` to trace where outbound requests actually go — SSRF surface

## 1. Authentication & JWT

- Signature verified with a safe algorithm (RS256/ES256, or HS256 with a strong secret)
- Algorithm pinned server-side — the token's own `alg` header is never trusted
  (`alg: none`, RS256→HS256 confusion)
- `exp`, `nbf`, `aud`, and `iss` all validated
- Revocation check (blacklist, or a token version in the database) runs before the request
  is processed
- Tokens never logged or echoed in error responses
- Filter chain correct for the stack: servlet `Filter`/`OncePerRequestFilter` or reactive
  `WebFilter`, registered ahead of protected endpoints

## 2. Input validation & injection

- All client input validated at the controller/handler boundary
- Parameterized queries at every persistence layer:
  - **JPA/Hibernate** — `@Query(nativeQuery = true)` and `createQuery()`/`createNativeQuery()`
    built by concatenation; user-controlled `Sort`/`Pageable` reaching `ORDER BY`
  - **R2DBC** — `DatabaseClient.sql()` with string interpolation instead of `bind()`
  - **JDBC** — `Statement` instead of `PreparedStatement`
  - **jOOQ** — `DSL.field()` / `condition()` built from raw strings
  - **MyBatis** — `${}` (direct interpolation) instead of `#{}` (bound parameter)
- Dynamic table or column names cannot be bound as parameters — require an allowlist
- No `eval`, SpEL, or template engine evaluating user input (SSTI / expression injection)
- Unsafe deserialization — Jackson polymorphic typing, `ObjectInputStream`, YAML `load()`

**Dangerous sinks by language:**

- **Python** — `pickle.loads`, `yaml.load` without `SafeLoader`, `eval`/`exec`,
  `subprocess` with `shell=True`, f-strings or `%` inside SQL, user input in
  `os.path.join` (path traversal), Jinja2 `render_template_string`
- **PHP** — `unserialize()` on user input (POP chains), `eval`, `system`/`exec`/`shell_exec`,
  dynamic `include`/`require` (LFI/RFI), `extract()`, `==` when comparing hashes or tokens
  (type juggling)
- **Go** — `template.HTML`/`template.JS` on user input (bypasses auto-escaping),
  `exec.Command` with a concatenated argument, paths from user input without
  `filepath.Clean` plus a prefix check
- **Java** — the persistence matrix above, plus `Runtime.exec` and XXE
  (`DocumentBuilderFactory` without DTDs disabled)

## 3. Sensitive data

- Passwords, tokens, and PII never appear in logs
- Stack traces never returned to the client
- `.env` files and config secrets never committed

## 4. Container & Kubernetes

**Dockerfile:**
- [ ] Does not run as root — a non-root `USER` before `CMD`/`ENTRYPOINT`
- [ ] Base image pinned (version tag or digest), not `:latest`
- [ ] No secrets in `ENV`/`ARG` — those values persist in the image layers permanently
- [ ] Multi-stage build so build tooling and source do not ship in the final image
- [ ] No `COPY . .` dragging in `.git`, `.env`, or credentials (check `.dockerignore`)

**Kubernetes manifests:**
- [ ] `securityContext`: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`,
      `readOnlyRootFilesystem: true`
- [ ] No `privileged: true`, `hostNetwork`, `hostPID`, or a mounted `/var/run/docker.sock`
- [ ] Capabilities `drop: [ALL]`, adding back only what is required
- [ ] Secrets via `Secret` or an external secret manager, never plaintext `env` or ConfigMap
- [ ] `resources.limits` set (prevents resource exhaustion and noisy neighbours)
- [ ] `automountServiceAccountToken: false` when the API server is not needed;
      RBAC least-privilege with no `cluster-admin` or wildcard verbs
- [ ] NetworkPolicy restricts pod-to-pod traffic instead of defaulting to allow-all

## 5. OWASP Top 10 pass

- [ ] A01 Broken Access Control — endpoints protected; check IDOR (object-level authorization)
      and mass assignment (entity bound directly to a request body)
- [ ] A02 Cryptographic Failures — no MD5/SHA1 for passwords; use bcrypt or argon2
- [ ] A03 Injection — SQL/NoSQL/LDAP, per the sink matrix above
- [ ] A05 Security Misconfiguration — default config, debug mode, CORS, security headers
- [ ] A07 Authentication Failures — brute-force protection and rate limiting
- [ ] A09 Logging Failures — audit trail exists without leaking sensitive data
- [ ] A10 SSRF — outbound URLs from user input validated (allowlist, block internal ranges
      and cloud metadata endpoints)

## Output format

Use the shared severity scale. One finding per line:

```
[CRITICAL] Title — file:line — impact — recommended fix
[HIGH]     Title — file:line — impact — recommended fix
[MEDIUM]   Title — file:line — impact — recommended fix
[LOW]      Title — file:line — impact — recommended fix
```
