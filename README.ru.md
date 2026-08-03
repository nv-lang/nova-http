[English](README.md) | **Русский**

# nova-http

HTTP/1.1-клиент и протокольное ядро для [Nova](https://nv-lang.org) —
модель запрос/ответ (`Method`, `StatusCode`, `Version`, `HeaderMap`,
`Body`), разбор URL со строгим валидатором host/SSRF, куки (RFC 6265bis) и
`HttpClient` (билдер в стиле reqwest: редиректы, распаковка
gzip/deflate/brotli, типизированные JSON-тела). HTTPS идёт через
[`tls`](../nova-tls). **В этом пакете НЕТ HTTP-сервера** — маршрутизатор
`Router`, обработчики, middleware, авторизация и WebSocket-слой живут в
[`nova-polaris`](https://github.com/nv-lang/nova-polaris).

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
Публичный API для оставшейся поверхности (протокольные типы + `HttpClient`)
не изменился по сравнению с `std.http` — сдвинулся только путь модуля
(`std.http.*` -> `http.*`; см. заметку «Путь модуля» ниже).

Позднее разбиение ([план 222](https://github.com/nv-lang/nova/blob/main/docs/plans/222-http-framework.md),
решение владельца 2026-07-24, коммит `d580e78`) вынесло сервер, `Router`,
middleware, авторизацию и WebSocket-слой из этого пакета ЦЕЛИКОМ в
[`nova-polaris`](https://github.com/nv-lang/nova-polaris), под путь модуля
`polaris.*` (не `http.server.*`) — это другой пакет, а не просто другой
путь модуля. В этом пакете осталось только то, что описано ниже:
протокольное ядро (типы) и клиент.

## Использование

```nova
import http.{Http}
import http.client.{HttpClient}
import http.transport.{real_http}
import std.net.{real_net}

fn main() {
    with Net = real_net(), Http = real_http() {
        ro resp = HttpClient.new().get("http://example.com/").send()!!
        println("status: ${resp.status().code()}")
        resp.drain()!!
    }
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
использует эту форму; доменные подпапки (`client/`, `serdejson/`,
`transport/`) — обычные пиры-папки-модули, объявляющие `module
http.client`, `module http.serdejson` и т. д. — по форме не отличаются от
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

## Тестирование клиента без сокетов

`Http` — это тонкий, подменяемый эффект-шов (`effect.nv`) между чистой
Nova-логикой клиента (редиректы, срез авторизации, `error_for_status`, ...)
и байтовым транспортом. Прод-код устанавливает `real_http()`
(`transport/real.nv`, поверх `Net`); тесты вместо этого устанавливают
`mock_http()` (`client/mock.nv`) — обработчик `Http` в памяти, который
маршрутизирует сериализованный запрос к запрограммированному
`MockResponse` по паре `(method, path)`, без единого сокета. Ответ проходит
через ТОТ ЖЕ проводной кодек, что использует `real_http()`, так что
фикстуры на chunked-декод и на битый ответ проверяют тот же самый парсер.

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

Встроенный обработчик `effect Http { send(..) { m.reply(request) } }`
захватывает `m` по кадру — это нужно, чтобы консервативный сборщик мусора
видел маршруты мока достижимыми (`mock_http().on(..).build()` тоже
работает, но копирует маршруты в незакорнённое хип-замыкание — см.
`[M-178-mock-handler-gc-trace]` в `client/mock.nv`).

## Лицензия

Двойная лицензия — [MIT](LICENSE-MIT) или [Apache-2.0](LICENSE-APACHE), на
ваш выбор — те же условия, что у компилятора Nova и стандартной библиотеки.

## Дорожная карта

- **`serve_static(mux, fs ReadFs)` + mime-по-расширению** (owner-go 2026-07-16): статик-хендлер поверх
  read-only VFS-протокола `ReadFs` (nova std/fs, Plan 210 Ф.6б) — «dev = с диска (`DirFs`), prod = из
  бинаря (`EmbeddedDir`/`embed_dir`)» одной строкой; Go `http.FileServer`-паритет. Mime-таблица по
  расширению (минимальный набор: html/css/js/json/svg/png/jpg/woff2/wasm + `application/octet-stream`
  fallback). Витрина — флагман-агрегатор (nova Plan 187): `embed_dir("frontend")` + `serve_static`.
