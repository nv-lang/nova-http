**English** | [Русский](README.ru.md)

# nova-http

HTTP/1.1 client + protocol core for [Nova](https://nv-lang.org) —
request/response model (`Method`, `StatusCode`, `Version`, `HeaderMap`,
`Body`), URL parsing with a strict host/SSRF validator, cookies (RFC
6265bis), and an `HttpClient` (reqwest-style builder: redirects,
gzip/deflate/brotli decompression, typed JSON bodies). HTTPS goes through
[`tls`](../nova-tls). **There is no HTTP server in this package** — the
`Router`, handlers, middleware, auth and WebSocket layer live in
[`nova-polaris`](https://github.com/nv-lang/nova-polaris).

Pure Nova — no native C shim of its own; external dependencies are `tls`
(for the `secure = true` transport path) and `compress` (for transparent
gzip/deflate/brotli response decompression, Plan 205 Ф.2). Transport for
plaintext HTTP and TCP sockets comes from the standard library (`std.net`).

Extracted from the Nova monorepo's `std/http` (Plan 178 core design) into a
standalone repository per
[Plan 203](https://github.com/nv-lang/nova/blob/main/docs/plans/203-http-out-of-std.md)
— bare HTTP without TLS is rarely useful on its own and the pairing mirrors
`nova-tls`'s own extraction ([Plan 193](https://github.com/nv-lang/nova/blob/main/docs/plans/193-nova-tls-repo.md)):
Rust and Swift both keep `http`+`tls` outside their standard library: this
package follows that school, continuing the direction set by nova-tls.
Public API for the surface that remains (protocol types + `HttpClient`) is
unchanged from `std.http` — only the module path moved (`std.http.*` ->
`http.*`; see "Module path" note below).

A later split ([Plan 222](https://github.com/nv-lang/nova/blob/main/docs/plans/222-http-framework.md),
owner decision 2026-07-24, commit `d580e78`) moved the server, `Router`,
middleware, auth and WebSocket layer OUT of this package entirely into
[`nova-polaris`](https://github.com/nv-lang/nova-polaris), under the
`polaris.*` module path (not `http.server.*`) — a different package, not
just a different module. This package kept only what's below: the protocol
core (types) and the client.

## Usage

```nova
import http.{Http}
import http.client.{HttpClient}
import http.transport.{real_http}
import std.net.{real_net}

fn main() {
    with Net = real_net() {
        with Http = real_http() {
            ro resp = HttpClient.new().get("http://example.com/").send()!!
            println("status: ${resp.status().code()}")
            resp.drain()!!
        }
    }
}
```

## Layout

```
nova-http/
├── nova.toml              [package] name = "http"; [lib] src = "src"; [dependencies] tls, compress
└── src/
    ├── body.nv             Body (+ BodyReader) — MUST-CONSUME (D359)
    ├── cookie.nv           Cookie / SetCookie (RFC 6265bis, D358)
    ├── effect.nv           the `Http` client transport seam (D357)
    ├── error.nv            HttpError (unified structural error, D358/D325)
    ├── header.nv           HeaderName / HeaderValue / HeaderMap (D358)
    ├── message.nv          Request / Response value model (D358)
    ├── method.nv           Method (D358)
    ├── mime.nv             Mime / ContentType (D358)
    ├── response_ext.nv     client-facing Response methods (D360)
    ├── status.nv           StatusCode (D358)
    ├── url.nv              URL parser + strict host/SSRF validator (D357-D358)
    ├── version.nv          HTTP version (D358)
    ├── *_test.nv           root-peer tests (same-module, positive)
    ├── neg/                EXPECT_COMPILE_ERROR fixtures (standalone CUs)
    ├── client/             HttpClient + reqwest-style builder, wire codec, mock transport (D357/D360)
    ├── serdejson/          typed JSON body decode (D360)
    └── transport/          real_http() over `Net`/`tls` (D357)
```

## Module path

D78 rev-4 (root peers, `spec/decisions/07-modules.md` "Root peers —
`.nv`-файлы прямо в source root") lets `.nv` files that sit directly in the
package's source root (`src/`, per `[lib] src` above) declare the
single-segment `module <package_name>` form — a peer group analogous to
Cargo's `lib.rs`. This package's root-level surface (`body`, `cookie`,
`effect`, `error`, `header`, `message`, `method`, `mime`, `response_ext`,
`status`, `url`, `version`, all declaring `module http`) uses that form;
domain subfolders (`client/`, `serdejson/`, `transport/`) are ordinary
folder-module peers declaring `module http.client`, `module
http.serdejson`, etc. — unchanged in shape from inside the monorepo
(`std/src/http/**`), only the enclosing `http/` directory itself
disappeared (it IS this package's source root now). Import as
`import http.{Http, ...}` / `import http.client.{HttpClient}` / etc., both
from another package's `[dependencies]` consumer and from an independent
same-package file (e.g. `src/neg/*.nv` uses `import http.{Body}` to reach
the root peers).

Before this extraction, these files lived at `std/src/http/**` and declared
`module std.http` (root files) / `module http.client` etc. (subfolders,
unchanged) — migrated out of `std` 2026-07-13 (Plan 203).

## Building standalone

Requires the Nova toolchain (`nova` CLI + clang). `[dependencies]` declares
the release form (`tls = { git = "https://github.com/nv-lang/nova-tls",
version = "0.1" }`, same for `compress`) — `nova.lock.toml` pins the resolved
tag+commit, fetched into the shared `~/.nova/git` cache on first build
(network required once).

For local development against a sibling checkout of
[`nova-tls`](https://github.com/nv-lang/nova-tls) and/or
[`nova-compress`](https://github.com/nv-lang/nova-compress) instead, create
a `nova.override.toml` (NOT committed — see `.gitignore`) next to this file:

```toml
[replace]
tls = { path = "../nova-tls" }
compress = { path = "../nova-compress" }
```

(Plan 204 дофикс №2 / D420: a committed `[replace]` would break a clean
clone whose override path only exists on the author's machine — `nova
build` hard-errors on that, `E_REPLACE_IN_MANIFEST`.)

```sh
# Boehm GC (mandatory Nova runtime dep) needs its own lib/include dirs —
# point NOVA_GC_LIB_DIR (+ optional NOVA_GC_INCLUDE_DIR) at a prebuilt
# bdwgc if it isn't reachable via the default vcpkg/system lookup
# (see compiler-codegen/src/test_runner.rs detect_boehm).
#
# `nova` does not (yet) bundle/locate the standard library relative to the
# nova.exe install — a standalone package must point it at a Nova checkout's
# std/ via NOVA_STD_PATH (compiler-codegen/src/manifest.rs resolve_std_path):
export NOVA_STD_PATH=/path/to/nova/std

# Ditto for the compiler's own C runtime (compiler-codegen/nova_rt/ + the
# libuv submodule it needs) — NOVA_CG_INCLUDE / NOVA_RT_DIR, symmetric with
# NOVA_STD_PATH above (resolve_paths in nova-cli/src/main.rs):
export NOVA_CG_INCLUDE=/path/to/nova/compiler-codegen
export NOVA_RT_DIR=/path/to/nova/compiler-codegen/nova_rt

# Use `nova test`, not `nova build <single-file>`, for anything beyond a
# syntax/import smoke check — this package has no `main`.
nova test src
```

## Gate

The package gate (Plan 222 §9, owner decision 2026-07-23) is
`scripts/gate.ps1` — run it before merging anything:

```powershell
# env NOVA_STD_PATH / NOVA_CG_INCLUDE / NOVA_RT_DIR set as above;
# $env:NOVA optionally points at a specific nova.exe
powershell -File scripts/gate.ps1            # optionally: -TestTimeout 300
```

Two mandatory steps, in order:

1. **`nova check src --strict-effects`** — the whole package must type-check
   with undeclared transitive effects as *errors*. Only the deliberate
   `src/neg/*` EXPECT_COMPILE_ERROR fixtures may FAIL; any other FAIL is a
   gate failure. Rationale: a package gate without `--strict-effects` does
   not catch effect bombs that only detonate in a consumer compile-unit
   built with the flag (precedent: the background/log default-sink
   `E_UNDECLARED_TRANSITIVE_EFFECT` found by the flagship build, commit
   4019173).
2. **`nova test src`** — the full test suite over the C-codegen pipeline.

## Testing the client without sockets

`Http` is a thin, mockable effect seam (`effect.nv`) between the pure-Nova
client logic (redirects, auth-strip, `error_for_status`, ...) and the byte
transport. Production code installs `real_http()` (`transport/real.nv`,
over `Net`); tests install `mock_http()` (`client/mock.nv`) instead — an
in-memory `Http` handler that routes a serialized request to a programmed
`MockResponse` by `(method, path)`, with no socket involved. It runs the
response through the SAME wire codec `real_http()` uses, so chunked-decode
and malformed-response fixtures exercise the identical parser.

```nova
test "client: GET round-trip via mock" {
    ro m = mock_http().on("GET", "/hello", MockResponse.new(200).text("world"))
    with Http = effect Http { send(host, port, secure, request) -> Result[str, HttpError] { m.reply(request) } } {
        ro resp = HttpClient.new().get("http://api.example.com/hello").send()!!
        assert(resp.status().code() == 200)
        assert(resp.into_text()!! == "world")
    }
}
```

The inline `effect Http { send(..) { m.reply(request) } }` handler captures
`m` by-frame — needed for the conservative GC to keep the mock's routes
reachable (`mock_http().on(..).build()` also works but copies the routes
into an unrooted heap closure — see `[M-178-mock-handler-gc-trace]` in
`client/mock.nv`).

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at
your option — same terms as the Nova compiler and standard library.

## Roadmap

- **`serve_static(mux, fs ReadFs)` + extension-based mime** (owner-go 2026-07-16): a static handler on
  top of the read-only VFS protocol `ReadFs` (nova std/fs, Plan 210 Ф.6б) — "dev = from disk (`DirFs`),
  prod = from the binary (`EmbeddedDir`/`embed_dir`)" in one line; parity with Go's `http.FileServer`.
  Extension-based mime table (minimal set: html/css/js/json/svg/png/jpg/woff2/wasm +
  `application/octet-stream` fallback). Showcase — the flagship aggregator (nova Plan 187):
  `embed_dir("frontend")` + `serve_static`.
