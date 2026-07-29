---
name: php-backend
description: PHP backend idioms — strict types and the type-juggling trap, modern PHP 8 features (enums, readonly, constructor promotion), typed exceptions, PDO prepared statements, Laravel and Symfony conventions, Eloquent N+1, service container usage, and the request lifecycle. Use when writing, changing, or reviewing PHP server code, or when composer.json is present.
globs:
  - "**/*.php"
  - "**/composer.json"
alwaysApply: false
---

# PHP Backend — Idioms & Conventions

## Strict types and comparison

```php
<?php
declare(strict_types=1);   // first line of every file, before anything else
```

Without it, PHP coerces arguments silently and a `string` reaches an `int` parameter
unnoticed.

Loose comparison is the classic PHP security bug, not just a style issue:

```php
// Dangerous — type juggling
if ($userToken == $storedToken) { }        // "0e123" == "0e456" is true (scientific notation)
if ($input == 0) { }                       // "abc" == 0 was true before PHP 8

// Correct
if ($userToken === $storedToken) { }
if (hash_equals($storedToken, $userToken)) { }   // timing-safe, for secrets
```

Use `===`/`!==` everywhere. For tokens, signatures, and hashes use `hash_equals`.

## Modern PHP 8

Write PHP 8, not PHP 5 with newer syntax:

```php
final class OrderService
{
    public function __construct(              // constructor property promotion
        private readonly OrderRepository $orders,
        private readonly LoggerInterface $logger,
    ) {}

    public function cancel(OrderId $id): Order
    {
        $order = $this->orders->find($id)
            ?? throw new OrderNotFound($id);   // throw as an expression
        return match ($order->status) {        // match is strict, exhaustive
            Status::Pending, Status::Paid => $order->cancel(),
            Status::Shipped => throw new CannotCancelShipped($id),
            Status::Cancelled => $order,
        };
    }
}

enum Status: string
{
    case Pending = 'pending';
    case Paid = 'paid';
    case Shipped = 'shipped';
    case Cancelled = 'cancelled';
}
```

- Backed **enums** instead of class constants or magic strings
- `readonly` properties for value objects; `final` by default unless designed for extension
- `match` rather than `switch` — strict comparison, no fallthrough, returns a value
- Typed properties, parameter types, and return types everywhere including `void` and `never`
- Nullsafe operator `?->` instead of nested null checks

## Errors and exceptions

- Signal failure with a typed exception, never a `false`/`null` return that callers forget
  to check
- Domain exception hierarchy extending a base app exception; catch narrowly
- Never use the `@` error-suppression operator — it hides the failure and keeps going
- Preserve the chain: `throw new PaymentFailed('gateway rejected', previous: $e)`
- Convert exceptions to HTTP responses in one handler (Laravel `Handler`, Symfony
  `kernel.exception` listener), not inside controllers
- `set_error_handler` to turn warnings into `ErrorException` so they cannot be ignored

## Database

```php
// Always prepared statements — never interpolation
$stmt = $pdo->prepare('SELECT * FROM users WHERE email = :email');
$stmt->execute(['email' => $email]);
```

- PDO configured to throw: `PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION`, and
  `PDO::ATTR_EMULATE_PREPARES => false` so binding happens server-side
- **Eloquent N+1** is the most common Laravel performance defect — `with()` eager loading,
  and enable `Model::preventLazyLoading()` in non-production so it fails loudly
- Keep the transaction boundary in a service (`DB::transaction(...)`), not spread across
  controllers
- Mass assignment: `$fillable` explicit, never `$guarded = []` — that hands the request
  body direct write access to every column

## Framework conventions

**Laravel**
- Constructor injection through the container; avoid `app()` and facades inside domain code
- Form Requests for validation so controllers stay thin
- Queue anything slow (email, PDF, external calls); the request path stays fast
- `config()` only — never `env()` outside config files, because config caching returns null
- Eloquent for persistence, but keep business rules in services, not models

**Symfony**
- Autowired services, constructor injection, `final` service classes
- DTOs plus the Validator component at the boundary
- Doctrine: watch the identity map and flush boundaries; `EntityManager` per request

## Runtime model

- PHP is **shared-nothing** — each request starts fresh. There is no in-process cache
  between requests unless you use OPcache, APCu, or Redis
- Enable OPcache in production; without it every request recompiles
- Long-running runtimes (Swoole, RoadRunner, Octane) break that assumption: static state now
  leaks between requests. Audit for it before adopting one
- `composer install --no-dev --optimize-autoloader` for production builds

## Review checklist

- [ ] `declare(strict_types=1)` in every file
- [ ] `===` used throughout; `hash_equals` for secret comparison
- [ ] Typed properties, parameters, and return types
- [ ] Enums instead of magic strings
- [ ] Typed exceptions, no `@` suppression, causes preserved
- [ ] Prepared statements; PDO in exception mode with emulation off
- [ ] Eager loading where relations are traversed; `$fillable` explicit
- [ ] PSR-12 formatting, PSR-4 autoloading, no manual `require`
- [ ] No `env()` outside config; slow work queued

## Related modules

- Cross-language service design → `backend-patterns`
- `unserialize` POP chains, dynamic includes, type-juggling auth bypass → `security-audit`
