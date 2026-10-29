# Benchmark History

The performance of `mercury_client` over its versions, on the VM, Chrome (JS)
and Chrome (Wasm). See [README.md](README.md) to run the benchmarks.

- Lower `µs/op` is better.
- `client (no network)` and `HttpCache` use a requester that answers at once:
  they measure the client itself (URLs, headers, bodies, responses).
- `network` uses the local test server (`test/test_server.dart`), in a VM
  isolate.
- Browser `network` rows vary ±30% between runs on the same machine. Compare
  them only within one run, or by running versions back to back (see
  2.4.0).
- Chrome runs use the `dart test` build (not a `-O4` release build).

To add a version: run `./benchmark/run.sh` and add its section at the top,
with the environment and the main changes.

---

## 2.4.0

- Environment: Apple M5, macOS, Dart 3.13.5, Chrome 156.
- Main changes (vs 2.3.3):
  - VM: the response body is read in chunks (`BytesBuilder`), not one byte at
    a time (`expand`): a 1MB download **4.4x** faster, a 256KB echo
    **3.6x**.
  - `HttpCache`: the entries are kept ordered by size (`SplayTreeSet`), the
    used memory is a running total, and a lookup is one map access: a miss
    with a memory limit **175x** (VM) to **265x** (Wasm) faster.
  - No asynchronous step when there's nothing to await (an authorization
    already resolved, no interceptor): a request **30%** (VM), **35%** (JS)
    and **41%** (Wasm) faster.
  - `HttpStatus` checks without allocating lists (**2.8x** VM, **30x** JS).
  - Browser: the request body converted with `toJS` (not the deep `jsify`):
    a 256KB upload **~18%** faster on Wasm (paired runs, below).
  - Correctness costs: a byte view (`sublistView`) is now copied by
    `asByteBuffer` (it returned the whole underlying buffer), and `HttpCache`
    copies the request parameters and body of its keys (`HttpCache hit` on
    JS: 6-8% slower; faster on the VM and Wasm).
- Tried and dropped: decoding UTF-8 with the browser's `TextDecoder`. A
  network text response was not faster, and on Wasm bytes from Dart memory
  were slower to decode (58.8 -> 104 µs for 24KB).

### VM

| Benchmark | µs/op | ops/s |
|---|---:|---:|
| GET with parameters | 1.360 | 735209 |
| GET JSON (getJSON) | 1.138 | 878727 |
| POST JSON body | 1.779 | 562171 |
| POST form parameters | 1.560 | 641148 |
| POST 16KB bytes | 1.693 | 590697 |
| GET with Basic authorization | 1.005 | 994932 |
| HttpCache hit | 1.275 | 784157 |
| HttpCache miss (memory limit) | 1.472 | 679352 |
| buildURLWithQueryParameters | 0.782 | 1279499 |
| HttpStatus.isError (x10) | 0.023 | 42930968 |
| HttpRequest header getters (x4) | 0.234 | 4279783 |
| HttpBody bytes asString (24KB UTF-8) | 28.0 | 35729 |
| HttpBody view asByteBuffer (24KB) | 0.845 | 1183354 |
| network: GET JSON (echo) | 119.8 | 8350 |
| network: GET 1MB bytes | 6996.1 | 143 |
| network: GET 256KB UTF-8 text (bodyAsString) | 1382.6 | 723 |
| network: POST 256KB bytes (echoed) | 2379.7 | 420 |

### Chrome (JS)

| Benchmark | µs/op | ops/s |
|---|---:|---:|
| GET with parameters | 3.433 | 291284 |
| GET JSON (getJSON) | 3.200 | 312452 |
| POST JSON body | 4.196 | 238329 |
| POST form parameters | 4.459 | 224268 |
| POST 16KB bytes | 4.183 | 239058 |
| GET with Basic authorization | 3.070 | 325706 |
| HttpCache hit | 4.210 | 237520 |
| HttpCache miss (memory limit) | 4.817 | 207618 |
| buildURLWithQueryParameters | 1.576 | 634499 |
| HttpStatus.isError (x10) | 0.010 | 98524501 |
| HttpRequest header getters (x4) | 0.301 | 3318680 |
| HttpBody bytes asString (24KB UTF-8) | 23.4 | 42658 |
| HttpBody view asByteBuffer (24KB) | 0.870 | 1149380 |
| network: GET JSON (echo) | 323.5 | 3091 |
| network: GET 1MB bytes | 8828.2 | 113 |
| network: GET 256KB UTF-8 text (bodyAsString) | 1951.5 | 512 |
| network: POST 256KB bytes (echoed) | 2823.2 | 354 |

### Chrome (Wasm)

| Benchmark | µs/op | ops/s |
|---|---:|---:|
| GET with parameters | 1.458 | 685760 |
| GET JSON (getJSON) | 1.249 | 800863 |
| POST JSON body | 1.896 | 527490 |
| POST form parameters | 1.978 | 505552 |
| POST 16KB bytes | 2.789 | 358556 |
| GET with Basic authorization | 1.154 | 866870 |
| HttpCache hit | 1.555 | 642900 |
| HttpCache miss (memory limit) | 1.569 | 637440 |
| buildURLWithQueryParameters | 1.167 | 856915 |
| HttpStatus.isError (x10) | 0.036 | 27699882 |
| HttpRequest header getters (x4) | 0.769 | 1299873 |
| HttpBody bytes asString (24KB UTF-8) | 60.4 | 16557 |
| HttpBody view asByteBuffer (24KB) | 0.927 | 1078792 |
| network: GET JSON (echo) | 305.9 | 3269 |
| network: GET 1MB bytes | 10099.6 | 99 |
| network: GET 256KB UTF-8 text (bodyAsString) | 2151.9 | 465 |
| network: POST 256KB bytes (echoed) | 3568.3 | 280 |

### Browser network: 2.3.3 and 2.4.0 back to back

Two rounds, each version right after the other (µs/op):

| Benchmark | JS 2.3.3 | JS 2.4.0 | Wasm 2.3.3 | Wasm 2.4.0 |
|---|---:|---:|---:|---:|
| GET JSON (echo) | 295.1 / 464.6 | 263.4 / 488.9 | 502.8 / 436.3 | 474.7 / 429.3 |
| GET 1MB bytes | 9061.2 / 10314.5 | 8805.1 / 9603.9 | 9529.8 / 9791.0 | 10315.3 / 9302.7 |
| GET 256KB UTF-8 text | 2023.8 / 2370.2 | 2168.8 / 2408.9 | 2952.5 / 2327.5 | 2480.1 / 2333.1 |
| POST 256KB bytes (echoed) | 2752.5 / 3035.6 | 2727.0 / 3020.4 | 4701.0 / 4635.0 | 3809.4 / 3868.1 |

---

## 2.3.3 (baseline)

- Environment: Apple M5, macOS, Dart 3.13.5, Chrome 156 (the 2.4.0
  benchmarks run on the 2.3.3 code; the `GET 256KB UTF-8 text` row was
  added later, in a separate run).

### VM

| Benchmark | µs/op | ops/s |
|---|---:|---:|
| GET with parameters | 1.958 | 510734 |
| GET JSON (getJSON) | 1.714 | 583349 |
| POST JSON body | 2.326 | 429935 |
| POST form parameters | 2.089 | 478616 |
| POST 16KB bytes | 2.241 | 446295 |
| GET with Basic authorization | 1.594 | 627470 |
| HttpCache hit | 1.613 | 619954 |
| HttpCache miss (memory limit) | 257.1 | 3890 |
| buildURLWithQueryParameters | 0.829 | 1206454 |
| HttpStatus.isError (x10) | 0.065 | 15433110 |
| HttpRequest header getters (x4) | 0.245 | 4084233 |
| HttpBody bytes asString (24KB UTF-8) | 27.9 | 35898 |
| HttpBody view asByteBuffer (24KB) | 0.007 | 136764301 |
| network: GET JSON (echo) | 122.2 | 8182 |
| network: GET 1MB bytes | 31162.7 | 32 |
| network: GET 256KB UTF-8 text (bodyAsString) | 1522.1 | 657 |
| network: POST 256KB bytes (echoed) | 8658.8 | 115 |

`HttpBody view asByteBuffer`: 2.3.3 returned the view's whole underlying
buffer (wrong bytes), without copying.

### Chrome (JS)

| Benchmark | µs/op | ops/s |
|---|---:|---:|
| GET with parameters | 5.321 | 187927 |
| GET JSON (getJSON) | 4.973 | 201078 |
| POST JSON body | 6.012 | 166326 |
| POST form parameters | 6.138 | 162929 |
| POST 16KB bytes | 5.920 | 168918 |
| GET with Basic authorization | 5.010 | 199582 |
| HttpCache hit | 3.907 | 255948 |
| HttpCache miss (memory limit) | 505.3 | 1979 |
| buildURLWithQueryParameters | 1.596 | 626479 |
| HttpStatus.isError (x10) | 0.308 | 3244498 |
| HttpRequest header getters (x4) | 0.287 | 3480000 |
| HttpBody bytes asString (24KB UTF-8) | 23.7 | 42240 |
| HttpBody view asByteBuffer (24KB) | 0.102 | 9832447 |
| network: GET JSON (echo) | 251.8 | 3971 |
| network: GET 1MB bytes | 9024.7 | 111 |
| network: GET 256KB UTF-8 text (bodyAsString) | 1869.8 | 535 |
| network: POST 256KB bytes (echoed) | 2985.9 | 335 |

### Chrome (Wasm)

| Benchmark | µs/op | ops/s |
|---|---:|---:|
| GET with parameters | 2.457 | 406954 |
| GET JSON (getJSON) | 2.186 | 457428 |
| POST JSON body | 2.683 | 372686 |
| POST form parameters | 2.722 | 367369 |
| POST 16KB bytes | 3.231 | 309476 |
| GET with Basic authorization | 1.914 | 522400 |
| HttpCache hit | 1.959 | 510362 |
| HttpCache miss (memory limit) | 415.1 | 2409 |
| buildURLWithQueryParameters | 1.144 | 874438 |
| HttpStatus.isError (x10) | 0.314 | 3184897 |
| HttpRequest header getters (x4) | 0.747 | 1338766 |
| HttpBody bytes asString (24KB UTF-8) | 58.8 | 16997 |
| HttpBody view asByteBuffer (24KB) | 0.016 | 63468202 |
| network: GET JSON (echo) | 249.3 | 4011 |
| network: GET 1MB bytes | 8909.4 | 112 |
| network: GET 256KB UTF-8 text (bodyAsString) | 1791.3 | 558 |
| network: POST 256KB bytes (echoed) | 3203.1 | 312 |
