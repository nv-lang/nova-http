# nova-http

HTTP/1.1 client + server for [Nova](https://nv-lang.org) — request/response
model (`Method`, `StatusCode`, `Version`, `HeaderMap`, `Body`), URL parsing
with a strict host/SSRF validator, cookies (RFC 6265bis), an `HttpClient`
(reqwest-style builder: redirects, gzip/deflate/brotli decompression, typed
JSON bodies), and an `HTTP/1.1` server (`ServeMux`, streaming/SSE, live
accept loop over `std.net`). HTTPS goes through [`tls`](../nova-tls).

Pure Nova — no native C shim of its own; the only external dependency is
`tls` (for the `secure = true` transport path). Transport for plaintext
HTTP and TCP sockets comes from the standard library (`std.net`).

Extracted from the Nova monorepo's `std/http` (Plan 178 core design) into a
standalone repository per
[Plan 203](https://github.com/nv-lang/nova/blob/main/docs/plans/203-http-out-of-std.md)
— bare HTTP without TLS is rarely useful on its own and the pairing mirrors
`nova-tls`'s own extraction ([Plan 193](https://github.com/nv-lang/nova/blob/main/docs/plans/193-nova-tls-repo.md)):
Rust and Swift both keep `http`+`tls` outside their standard library: this
package follows that school, continuing the direction set by nova-tls.
Public API is unchanged from `std.http` — only the module path moved
(`std.http.*` -> `http.*`; see "Module path" note below).

## Usage

```nova
import http.{Http}
import http.client.{HttpClient}
import http.server.{ServeMux, ServerResponse, handler_fn, serve_once}

fn make_client() Http -> HttpClient {
    HttpClient.new()
}

fn make_mux() -> ServeMux {
    ro mux = ServeMux.new()
    mux.handle("/", handler_fn(fn(req) {
        ServerResponse.text(200, "hello from nova-http")
    }))
    mux
}
```

## Layout

```
nova-http/
├── nova.toml              [package] name = "http"; [lib] src = "src"; [dependencies] tls
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
    ├── server/             HTTP/1.1 server CORE + wire codec (D361)
    ├── servernet/          live accept loop over std.net (D361) + rt/ smoke tests
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
domain subfolders (`client/`, `server/`, `servernet/`, `serdejson/`,
`transport/`) are ordinary folder-module peers declaring `module
http.client`, `module http.server`, etc. — unchanged in shape from inside
the monorepo (`std/src/http/**`), only the enclosing `http/` directory
itself disappeared (it IS this package's source root now). Import as
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
version = "0.1" }`) — `nova.lock` pins the resolved tag+commit, fetched into
the shared `~/.nova/git` cache on first build (network required once).

For local development against a sibling checkout of
[`nova-tls`](https://github.com/nv-lang/nova-tls) instead, create a
`nova.local.toml` (NOT committed — see `.gitignore`) next to this file:

```toml
[replace]
tls = { path = "../nova-tls" }
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

Some tests (`servernet/rt/*`, live socket smoke tests) bind real ports and
may need a longer timeout (`--timeout 300`) than the default under load.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at
your option — same terms as the Nova compiler and standard library.
