# Effect Dependency Injection for Handlers

> **Note:** this pattern is illustrated with `Router`/`ServerRequest`/
> `ServerResponse` — those types do NOT live in this package (`nova-http`).
> The server/router/handler layer was split out into
> [`nova-polaris`](https://github.com/nv-lang/nova-polaris) (Plan 222,
> owner decision 2026-07-24); `nova-http` now carries only the protocol core
> and the client (see the [top-level README](../../README.md)). The
> effect-widening technique below is a general Nova pattern, not specific to
> either package — it applies wherever you have a fixed handler-like
> signature and want per-handler effect rows to widen into it.

## Problem: Factory ceremonies

Typically, handlers require external services — database pools, loggers,
config. Frameworks handle this through factories that wrap each handler:

```rust
// Pseudo-code (Rust idiom)
fn make_handler_with_deps(db: Pool, log: Logger) -> Handler {
    move |req| { /* db, log in closure */ }
}
```

This spreads the effect-setup ceremony across every route registration, tying
handlers to the factory's lifetime and shape.

## Solution: Fixed whole-app effect row

Instead of parameterizing handlers by a generic effect type, declare handlers
against a **fixed, closed effect row** representing the app's entire dependency
surface — and rely on **sub-effecting widening**: a handler that uses fewer
effects than the row declares automatically widens into slots expecting the
full row (D62, covariant position).

Define a single newtype wrapper over the handler function once:

```nova
type Db effect {
    find(id int) -> Option[str]
}
type Log effect {
    info(msg str) -> ()
}

// newtype-over-fn WITH an effect row (D52/D55) — call it directly, no
// constructor, no @handle: plain fns auto-lift into it (sub-effecting).
type AppHandler fn(ServerRequest) Db Log -> ServerResponse
```

Then define handlers with **narrower** effect rows — they widen for free (a plain `fn` with a subset of the row auto-lifts into `AppHandler`):

```nova
// Uses only Db — narrower than Handler's declared `Db Log` row.
fn create_user(req ServerRequest) Db -> ServerResponse {
    match Db.find(req.id) {
        Some(name) => ServerResponse.text(200, name)
        None       => ServerResponse.text(404, "not found")
    }
}

// Uses both Db and Log — exact match.
fn get_user_logged(req ServerRequest) Db Log -> ServerResponse {
    Log.info("fetching user ${req.id}")
    match Db.find(req.id) {
        Some(name) => ServerResponse.text(200, name)
        None       => ServerResponse.text(404, "not found")
    }
}

// Uses neither — the empty row widens to any declared row.
fn health(req ServerRequest) -> ServerResponse => ServerResponse.text(200, "ok")
```

At dispatch time, wrap a **single** `with` pair around the entire router,
not per-route. `Router`/`ServerRequest`/`ServerResponse` here are
`nova-polaris` types (`import polaris.{Router, ServerRequest,
ServerResponse}`) — `Router.@dispatch` is a real method
(`src/server_router.nv`):

```nova
import polaris.{Router, ServerRequest, ServerResponse}

fn serve_app(r Router, req ServerRequest) -> ServerResponse {
    with Db = effect Db {
        find(id int) -> Option[str] { /* real pool query */ }
    } {
        with Log = effect Log {
            info(msg str) -> () { /* real logger sink */ }
        } {
            r.dispatch(req)
        }
    }
}
```

## Benefits

1. **Compile-time guarantees**: forget to wire an effect the handler uses?
   Compiler error at the `with` site, not at runtime. Stronger than Axum's
   `State` extraction (which panics at runtime if missing) or FastAPI's
   `Depends` (which raises at request time).

2. **No heterogeneous erasure**: all handlers in the router share one effect
   signature — no need to erase generic type parameters or maintain
   per-route effect sets.

3. **Natural widening**: handlers can opt into effects they actually use. A
   health-check that needs nothing passes without ceremony.

4. **Single setup point**: the `with` stack wraps the whole dispatch once,
   making the app's dependency surface explicit and testable in isolation.

## Verification

Build with `nova check --strict-effects` to catch undeclared transitive
effects at compile time — in whichever package hosts your handlers. This
package's own gate (`Router`-free) is [Gate](../../README.md#gate); for
`nova-polaris`, where `Router`/`ServerRequest`/`ServerResponse` above
actually live, every documented code sample (including this pattern, once
ported there) is checked via `nova test src/doc_samples_test.nv` — see its
[README](https://github.com/nv-lang/nova-polaris#documentation).
