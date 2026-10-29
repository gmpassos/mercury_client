# Benchmarks

Benchmarks of `mercury_client` on the VM, Chrome (JS) and Chrome (Wasm):

- `client (no network)`: requests (URLs, headers, bodies, responses) with a
  requester that answers at once.
- `HttpCache`: cache hits, and misses with a memory limit.
- `utilities`: URLs, status checks, headers and body conversions.
- `network`: requests to the local test server (`test/test_server.dart`,
  started in a VM isolate with `spawnHybridUri`): JSON, a 1MB download, a
  256KB UTF-8 text and a 256KB upload.

## Run

All the platforms:

```shell
./benchmark/run.sh
```

Or some of them (`vm`, `js`, `wasm`):

```shell
./benchmark/run.sh vm wasm
```

Or one directly (each benchmark prints a Markdown table row):

```shell
dart test benchmark/mercury_client_benchmark.dart -p vm -r expanded
dart test benchmark/mercury_client_benchmark.dart -p chrome -r expanded
dart test benchmark/mercury_client_benchmark.dart -p chrome -c dart2wasm -r expanded
```

The benchmarks are not in `test/`, so `dart test` (and the CI) doesn't run
them.

## History

The results of each version are in [HISTORY.md](HISTORY.md), with the main
changes. Add the new version's tables at the top.
