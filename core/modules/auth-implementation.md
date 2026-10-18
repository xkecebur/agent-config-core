---
name: auth-implementation
description: Building authentication and authorisation — choosing between session cookies, JWTs, and a delegated identity provider; session cookie configuration; OAuth 2.1 / OIDC with state, PKCE, and nonce; refresh token rotation with reuse detection; password hashing, MFA, and recovery flows; object-level authorisation and where the check belongs; logout and session invalidation. Use when designing or writing login, registration, SSO, refresh tokens, a session store, step-up authentication, or 2FA. To review authentication that already exists, use security-audit instead.
alwaysApply: false
---

# Authentication & Authorisation — Implementation

This module is about **building**. To review authentication that already exists, use
`security-audit`.

The rule underneath everything: **authentication answers "who", authorisation answers "may
this identity do this to this object".** Most real-world loss comes from the second, not
the first.

## Choose the model before choosing a library

| Situation | Model | Why |
|---|---|---|
| Web app, client and server on one domain or subdomain | **Session cookie** to a server-side store | Instantly revocable, no token in JavaScript, least that can go wrong |
| Third-party clients, mobile, or service-to-service | **OAuth 2.1 + OIDC** | Do not invent a protocol |
| Internal microservices behind a gateway | **Short-lived JWT** issued by the gateway | Verification without a round trip; the gateway is the trust boundary |
| An identity provider already exists | **Delegate to the IdP** | MFA, conditional access, and audit are already built |

**JWT is not the default.** A JWT held as a browser session buys scalability and pays with
revocation. Without a real scale reason, a session cookie is safer and simpler.

If a JWT is still the session: keep the access token short-lived (5–15 minutes) and hold the
refresh token server-side so it can be revoked. Without that, logout and "revoke access" are
cosmetic.

## Session cookie — the minimum configuration

```
Set-Cookie: __Host-sid=<id>; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=<ttl>
```

- `HttpOnly` keeps the session out of reach of JavaScript, so one XSS cannot steal it
- The `__Host-` prefix locks the cookie to a single origin — it cannot be set from another
  subdomain. This is what kills cookie tossing from a subdomain that got taken over. It
  requires `Secure` and `Path=/`
- `SameSite=Lax` is **not** a CSRF token replacement for sensitive flows: sibling subdomains
  count as same-site
- **No token in `localStorage`.** Anything JavaScript can read, one XSS can exfiltrate
- **Regenerate the session id on login.** Without it, session fixation

## OAuth 2.1 / OIDC — what must be right

| Parameter | Purpose | If it is wrong |
|---|---|---|
| `state` | Binds the callback to the session that started it | Login CSRF — the victim's account is linked to the attacker's |
| PKCE `code_verifier` / `code_challenge` | Binds the code exchange to the same client | A leaked authorization code is redeemable by someone else |
| `nonce` | Binds the ID token to the request | ID token replay |
| `redirect_uri` | **Exact match** against a server-side allowlist | Authorization code theft → account takeover |

The `redirect_uri` rule is the one most often broken: matching is **exact string** — not a
prefix, not a regex, not "any subdomain of ours". One subdomain that can be taken over
becomes an account takeover.

Beyond the parameters:

- Validate `iss` and `aud` on the ID token, and the signature against the issuer's JWKS.
  Never trust the `alg` value carried in the token header
- Link accounts by email **only** when the provider asserts `email_verified: true`.
  Otherwise anyone who can register that email at the provider takes over the account
- Store the mapping as `provider + provider_user_id`, not email as the identity key — email
  changes hands and gets reused

## Refresh token rotation and reuse detection

Rotation without reuse detection only moves the problem.

1. Every exchange issues a new refresh token and **invalidates the previous one**
2. Store tokens hashed, in one chain (a `family`) per login session
3. If an already-invalidated token is presented again, that is evidence of a leak → **revoke
   the whole family**, force re-authentication, and record it as a security event

Send the refresh token in an `HttpOnly` cookie scoped by `Path` to the refresh endpoint, not
in a body that JavaScript can touch.

## Passwords, MFA, and recovery flows

- Hash with **argon2id**, or **bcrypt** where argon2 is unavailable. Never a bare
  MD5/SHA-family digest, never without a salt. Take cost parameters from the current OWASP
  guidance — look them up rather than recalling a number
- Compare hashes and tokens with a **constant-time** comparison, never `==`
- A minimum length plus a check against a breached-password list beats character-composition
  rules
- Rate limit and lock out login, OTP, and reset. A six-digit OTP with no rate limit is worth
  exactly 10^6 attempts
- TOTP: a small acceptance window (±1 step), and a code that has been used **must not be
  accepted twice**
- Recovery codes: hashed at rest, single use, displayed once at creation
- Password reset tokens: cryptographically random, stored hashed, single use, short
  expiry — **and invalidate every session once the password changes**
- Build the reset URL from configuration, **never from the request `Host` header**.
  Otherwise host header injection delivers the token to the attacker

## Authorisation — where it actually leaks

- Check on the **server**, as close to the data access as possible. A hidden UI button is
  not a control
- It must be **object-level**: not merely "this user has the admin role" but "this record
  belongs to this tenant". Without that it is an IDOR
- Default deny. A new route is not automatically public
- Auth middleware must survive path variation: trailing slashes, case differences,
  percent-encoded traversal, and static asset paths
- Sensitive operations — changing email or password, deleting the account, moving money —
  require **step-up**: a password or MFA re-confirmation, not merely a valid session
- Logout revokes the session **on the server**, not just by clearing the browser cookie

## Backend-for-frontend — the browser holds a session, the server holds the credential

When the browser must reach an internal API that takes a privileged credential, put a thin
server of your own in between: the browser talks only to it with a session cookie, and the
credential never leaves the server. What goes wrong:

| Shortcut | Consequence |
|---|---|
| One shared service token for every user | Every request arrives upstream as the same caller. Audit trails lose the actor, per-caller rate limits become one bucket for the whole team, and any maker-checker rule (`approved_by <> requested_by`) rejects every approval |
| Forwarding any path the browser asks for | An open proxy to the whole internal API with the credential already attached. Allowlist the paths, mirroring the upstream's own default-deny |
| Streaming the request body straight upstream | The body-size limit is advisory. Read it first, then enforce the cap |
| Retrying failed upstream calls | A retried `POST` that moves money or changes state happens twice → `api-contract` (idempotency) |
| Rewriting upstream errors into a generic `500`, or a `200` | The client cannot tell a refusal from an outage. Forward the error body and status intact |
| Dropping `traceparent` | The browser request cannot be joined to the upstream logs → `blue-team-detection` |
| A sealed cookie carrying the credential itself | Cannot be revoked before it expires. The cookie carries a session id; the credential lives in a server-side store whose row can be deleted |

Forward the **user's** identity upstream — exchanged or minted per session — never a
credential the BFF holds for itself. Upstream timeouts, and what a timeout spans → `node-backend`.

**Server-side rendering and the BFF.** A loader that runs during server rendering and calls
the BFF by relative URL (`/api/...`) fails — there is no origin to resolve against, and the
server-side call would not carry the user's cookie anyway. Either render those routes
client-only, or make the server-side path forward the incoming cookie to an absolute
internal URL deliberately. A route that works on in-app navigation and returns `500` on a
direct load or refresh is the signature.

**Never guess an auth library's API.** Read the installed package or the official docs
first. A wrong argument in an auth configuration is a vulnerability, not a typo.

## Before claiming it is done

- [ ] Session id regenerated on login, revoked server-side on logout
- [ ] Cookie: `HttpOnly`, `Secure`, `SameSite`, `__Host-` prefix where possible
- [ ] No token in `localStorage` or `sessionStorage`
- [ ] OAuth: `state`, PKCE, `nonce`, exact-match `redirect_uri` from an allowlist
- [ ] Refresh tokens rotated, with reuse detection that revokes the family
- [ ] Passwords hashed with argon2id/bcrypt; constant-time comparison
- [ ] Rate limits on login, OTP, and password reset
- [ ] Password or email change revokes other sessions and requires step-up
- [ ] Object-level authorisation tested with **two real accounts**, not just two roles
- [ ] No auth secret reachable from client-side code → `security-audit`
- [ ] BFF: per-user identity forwarded upstream, path allowlist, body cap enforced, no
      retries of state-changing calls

## Related modules

`security-audit` for reviewing auth that already exists · `api-contract` for authorising
endpoints and error status codes · `backend-patterns` for token store and timeout
mechanics · `blue-team-detection` for what an auth security event should log
