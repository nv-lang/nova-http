[English](README.md) | **Русский**

# nova-http

HTTP/1.1-клиент и сервер для [Nova](https://nv-lang.org) — модель
запрос/ответ (`Method`, `StatusCode`, `Version`, `HeaderMap`, `Body`), разбор
URL со строгим валидатором host/SSRF, куки (RFC 6265bis), `HttpClient`
(билдер в стиле reqwest: редиректы, распаковка gzip/deflate/brotli,
типизированные JSON-тела) и сервер `HTTP/1.1` (`ServeMux`, streaming/SSE,
живой accept-цикл поверх `std.net`). HTTPS идёт через [`tls`](../nova-tls).

Чистый Nova — без своей нативной C-прослойки; внешние зависимости — `tls`
(для транспортного пути `secure = true`) и `compress` (для прозрачной
распаковки gzip/deflate/brotli в ответах, план 205 Ф.2). Транспорт для
обычного HTTP и TCP-сокетов приходит из стандартной библиотеки (`std.net`).

Извлечено из монорепозитория Nova, из `std/http` (базовый дизайн — план 178),
в отдельный репозиторий по
[плану 203](https://github.com/nv-lang/nova/blob/main/docs/plans/203-http-out-of-std.md)
— голый HTTP без TLS сам по себе редко полезен, и такое разбиение отражает
собственное извлечение `nova-tls` ([план 193](https://github.com/nv-lang/nova/blob/main/docs/plans/193-nova-tls-repo.md)):
и Rust, и Swift держат `http`+`tls` вне своей стандартной библиотеки — этот
пакет следует той же школе, продолжая направление, заданное nova-tls.
Публичный API не изменился по сравнению с `std.http` — сдвинулся только путь
модуля (`std.http.*` -> `http.*`; см. заметку «Путь модуля» ниже).

## Использование

```nova
import http.{Http}
import http.client.{HttpClient}
import http.server.{Router, ServerRequest, ServerResponse, serve_once}

fn make_client() Http -> HttpClient {
    HttpClient.new()
}

fn make_router() -> Router {
    mut r = Router.new()
    // A bare closure auto-lifts into `Handler` (newtype over
    // `fn(ServerRequest) -> ServerResponse`, D52/D55) — no wrapper call.
    r.get("/", fn(req ServerRequest) -> ServerResponse =>
        ServerResponse.text(200, "hello from nova-http"))!!
    r
}
```

## Структура

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
    ├── server/             HTTP/1.1 server CORE + wire codec (D361)
    ├── servernet/          live accept loop over std.net (D361) + rt/ smoke tests
    ├── serdejson/          typed JSON body decode (D360)
    └── transport/          real_http() over `Net`/`tls` (D357)
```

## Путь модуля

D78 rev-4 (root peers, `spec/decisions/07-modules.md` «Root peers —
`.nv`-файлы прямо в source root») позволяет `.nv`-файлам, лежащим прямо в
исходном корне пакета (`src/`, согласно `[lib] src` выше), объявлять
однокомпонентную форму `module <package_name>` — группу пиров, аналогичную
`lib.rs` в Cargo. Поверхность корневого уровня этого пакета (`body`,
`cookie`, `effect`, `error`, `header`, `message`, `method`, `mime`,
`response_ext`, `status`, `url`, `version`, все объявляют `module http`)
использует эту форму; доменные подпапки (`client/`, `server/`, `servernet/`,
`serdejson/`, `transport/`) — обычные пиры-папки-модули, объявляющие `module
http.client`, `module http.server` и т. д. — по форме не отличаются от
монорепозитория (`std/src/http/**`), исчезла только сама объемлющая папка
`http/` (теперь ею является исходный корень этого пакета). Импортировать как
`import http.{Http, ...}` / `import http.client.{HttpClient}` / и т. д., как
из `[dependencies]`-потребителя другого пакета, так и из независимого файла
того же пакета (например, `src/neg/*.nv` использует `import http.{Body}` для
доступа к корневым пирам).

До этого извлечения эти файлы жили в `std/src/http/**` и объявляли `module
std.http` (корневые файлы) / `module http.client` и т. д. (подпапки, без
изменений) — вынесены из `std` 2026-07-13 (план 203).

## Автономная сборка

Нужен тулчейн Nova (CLI `nova` + clang). `[dependencies]` объявляет
релизную форму (`tls = { git = "https://github.com/nv-lang/nova-tls",
version = "0.1" }`, аналогично для `compress`) — `nova.lock.toml` фиксирует
разрешённые тег+коммит, которые подтягиваются в общий кэш `~/.nova/git` при
первой сборке (один раз нужна сеть).

Для локальной разработки против соседнего чекаута
[`nova-tls`](https://github.com/nv-lang/nova-tls) и/или
[`nova-compress`](https://github.com/nv-lang/nova-compress) вместо этого
создайте `nova.override.toml` (НЕ коммитится — см. `.gitignore`) рядом с
этим файлом:

```toml
[replace]
tls = { path = "../nova-tls" }
compress = { path = "../nova-compress" }
```

(План 204, дофикс №2 / D420: закоммиченный `[replace]` сломал бы чистый
клон, чей путь override существует только на машине автора — `nova build`
жёстко падает на этом, `E_REPLACE_IN_MANIFEST`.)

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

Некоторым тестам (`servernet/rt/*`, живые тесты сокетов) нужны реальные
порты, и им может понадобиться более длинный таймаут (`--timeout 300`), чем
дефолтный, при нагрузке.

## Гейт

Гейт пакета (план 222 §9, решение владельца 2026-07-23) — это
`scripts/gate.ps1` — запускайте его перед любым слиянием:

```powershell
# env NOVA_STD_PATH / NOVA_CG_INCLUDE / NOVA_RT_DIR set as above;
# $env:NOVA optionally points at a specific nova.exe
powershell -File scripts/gate.ps1            # optionally: -TestTimeout 300
```

Два обязательных шага, по порядку:

1. **`nova check src --strict-effects`** — весь пакет должен пройти
   тайп-чек с необъявленными транзитивными эффектами как *ошибками*. Только
   намеренные фикстуры `src/neg/*` (EXPECT_COMPILE_ERROR) могут падать
   (FAIL); любой другой FAIL — провал гейта. Обоснование: гейт пакета без
   `--strict-effects` не ловит эффект-бомбы, которые срабатывают только в
   единице компиляции потребителя, собранной с флагом (прецедент:
   `E_UNDECLARED_TRANSITIVE_EFFECT` дефолтного sink'а фонового
   лога, найденный флагманской сборкой, коммит 4019173).
2. **`nova test src`** — полный набор тестов через пайплайн C-codegen.

## Тестирование обработчиков без сокетов

Обработчик — это просто функция, сокет не нужен. Архитектура Nova позволяет
тестировать поведение `Handler` напрямую, вызывая `dispatch` в тесте и
передавая синтетический запрос. В отличие от фреймворков, которым нужны
мок-транспорты или тяжеловесные заглушки `TestClient` (например, FastAPI
позиционирует свой `TestClient` как опциональный внешний инструмент), этот
паттерн встроен: диспетчеризация запроса — это чистый вызов функции. Чтобы
протестировать поведение маршрута без привязки портов, вызовите
`serve_once()` с маршрутизатором и сырыми байтами HTTP — в ответ вы получите
полный проводной ответ и разбираете его прямо на месте.

```nova
mut r = Router.new()
r.get("/hello", fn(req ServerRequest) -> ServerResponse => 
    ServerResponse.text(200, "hello"))!!
ro wire = serve_once(r, "GET /hello HTTP/1.1\r\nHost: x\r\n\r\n".bytes())
assert(status_line(wire) == "HTTP/1.1 200 OK")
```

## Лицензия

Двойная лицензия — [MIT](LICENSE-MIT) или [Apache-2.0](LICENSE-APACHE), на
ваш выбор — те же условия, что у компилятора Nova и стандартной библиотеки.

## Дорожная карта

- **`serve_static(mux, fs ReadFs)` + mime-по-расширению** (owner-go 2026-07-16): статик-хендлер поверх
  read-only VFS-протокола `ReadFs` (nova std/fs, Plan 210 Ф.6б) — «dev = с диска (`DirFs`), prod = из
  бинаря (`EmbeddedDir`/`embed_dir`)» одной строкой; Go `http.FileServer`-паритет. Mime-таблица по
  расширению (минимальный набор: html/css/js/json/svg/png/jpg/woff2/wasm + `application/octet-stream`
  fallback). Витрина — флагман-агрегатор (nova Plan 187): `embed_dir("frontend")` + `serve_static`.
