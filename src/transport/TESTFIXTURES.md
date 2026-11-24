# Test fixtures in this directory (NOT secrets)

The `*.pem` files here are SELF-SIGNED, LOOPBACK-ONLY test fixtures used by
`https_test.nv` via `embed(...)`:

- `localhost_cert.pem` / `localhost_key.pem` — self-signed ECDSA P-256 pair
  for CN/SAN `localhost`, expired 2126; server side of the native HTTPS
  tests (`TlsStream.accept`, `ServerConfig.new(https_cert(), https_key())`).
- `wrong_hostname_cert.pem` — a valid self-signed certificate whose name
  does NOT match `localhost` (CN `other.example`); drives the negative
  "trusted certificate with wrong hostname rejected" test. The key for it
  is intentionally NOT kept — only the certificate is embedded.

**НЕ секрет / NOT a secret.** Anyone can regenerate them; they only ever
terminate loopback connections inside `nova test src`. Secret scanners
should skip this directory; reviewers should not flag the private key.

Regenerate (from this directory):

```sh
# localhost pair (cert + key), 100-year validity, SAN localhost + 127.0.0.1
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout localhost_key.pem -out localhost_cert.pem -days 36500 \
  -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

# wrong-hostname certificate (negative test), key discarded
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout /dev/null -out wrong_hostname_cert.pem -days 36500 \
  -subj "/CN=other.example"
```

Git note: `localhost_key.pem` and `wrong_hostname_cert.pem`'s key are not
tracked as secrets — they are committed test fixtures alongside the
certificates.
