
[![Ceasefire Now](https://badge.techforpalestine.org/default)](https://techforpalestine.org/learn-more)

[:heart: sponsor](https://github.com/sponsors/rbellens)


A tool to integrate benchmarking into your development and testing workflow.

## Features

* Run benchmarks as unit tests
* Easily profile your code from VS code
* Compare benchmarks between different commits on github

## Usage

Add `benchmark_test` as a dev dependency:

```yaml
dev_dependencies:
  benchmark_test: ^0.0.2
```

Create a test file (for example `test/benchmarks_test.dart`) and use the `benchmark` function like a regular test:

```dart
import 'package:benchmark_test/benchmark_test.dart';

void main() {
  group('my benchmarks', () {
    benchmark('parse json', () {
      // code to benchmark
    });

    benchmark('parse json (long run)', () {
      // code to benchmark
    }, minDuration: Duration(seconds: 4), minSamples: 30);
  });
}
```

Run benchmarks with `dart test`:

```sh
dart test test/benchmarks_test.dart
```

Or use the package CLI to run the same benchmarks for multiple compile types:

```sh
dart run benchmark_test test/benchmarks_test.dart
```

The CLI currently supports `jit` and `aot` and runs both by default. Use
`--compile` to choose one or more compile types:

```sh
dart run benchmark_test --compile jit test/benchmarks_test.dart
dart run benchmark_test --compile jit,aot test/benchmarks_test.dart
```

Use `--output` to choose `human`, `benchmarkjs`, or `jsonl` output:

```sh
dart run benchmark_test --output jsonl test/benchmarks_test.dart
```

Pass additional `dart test` arguments after `--`:

```sh
dart run benchmark_test test/benchmarks_test.dart -- -n parse
```

### The `benchmark` method

`benchmark` registers a test that repeatedly executes the given function and prints performance statistics:

```
Benchmark: my benchmarks parse json
  12345.67 ops/sec
  ±2.34% margin of error
  42 runs sampled
  0:00:00.000081 average duration
```

The output includes:

* **ops/sec** — estimated operations per second
* **±%** — relative margin of error (95% confidence interval)
* **runs sampled** — number of iterations after the warm-up run
* **average duration** — mean time per iteration

#### Output formats

By default, benchmarks print a human-readable format. Set `BENCHMARK_OUTPUT` to choose another output format:

```sh
BENCHMARK_OUTPUT=benchmarkjs dart test test/benchmarks_test.dart
```

Supported values:

* `human` — default, optimized for local development
* `benchmarkjs` — benchmark.js-compatible output for tools like `github-action-benchmark`
* `ndjson` — one JSON object per benchmark result; `jsonl` is also accepted as an alias

`ndjson` output uses this schema:

```json
{"formatVersion":1,"name":"my benchmarks parse json","throughput":{"value":12345.67,"unit":"ops/sec"},"statistics":{"relativeMarginOfError":2.34,"samples":42},"latency":{"mean":81,"unit":"microseconds"}}
```

#### Baselines

Human output compares each benchmark against the baseline stored in `build/benchmark_test/baselines.json`. Baselines are read-only by default:

```sh
dart test test/benchmarks_test.dart
```

Create or overwrite the baseline by setting `BENCHMARK_UPDATE_BASELINE`:

```sh
BENCHMARK_UPDATE_BASELINE=true dart test test/benchmarks_test.dart
```

The comparison uses throughput, so higher `ops/sec` is an improvement and lower `ops/sec` is a regression. Changes of at least 5% are marked with `✅` for improvements or `⚠️` for regressions. Improvements and regressions are colored when ANSI colors are supported.

#### Parameters

| Parameter     | Default              | Description |
|---------------|----------------------|-------------|
| `minDuration` | `Duration(seconds: 2)` | Keep running until at least this much time has elapsed |
| `minSamples`  | `5`                  | Keep running until at least this many iterations have completed |
| `timeout`     | `minDuration * 2`    | Fail the test if it exceeds this duration |

The first iteration is treated as a warm-up run and is excluded from the statistics.

#### `setUpEach` and `tearDownEach`

Use these to run setup and teardown logic before and after every iteration (not just once per test):

```dart
import 'package:benchmark_test/benchmark_test.dart';

void main() {
  group('with setup', () {
    setUpEach(() {
      // runs before each iteration
    });

    tearDownEach(() {
      // runs after each iteration
    });

    benchmark('my benchmark', () {
      // ...
    });
  });
}
```

When called inside a nested `group`, they apply only to benchmarks within that group.

### Profile code from VS Code

To profile a benchmark with the Dart CPU profiler, add a launch configuration to `.vscode/launch.json`:

```json
{
  "name": "Profile",
  "request": "launch",
  "type": "dart",
  "codeLens": {
    "for": ["debug-test"]
  },
  "env": {"PROFILE_MODE": "true"}
}
```

When `PROFILE_MODE` is set to `true`, the benchmark pauses at the start and end of each test so you can start and stop CPU profiling in the debugger. Use the **Profile** code lens on a benchmark test to launch it in profile mode.

Tests do not run in the main isolate, so in the CPU profiler you must select the isolate where the test is running (often labeled something like `test_suite:... #2`) before starting recording. The benchmark prints these steps to the console when it pauses.

### Track benchmarks on GitHub

Create `.github/workflows/benchmark.yaml` to run benchmarks on every push to
`master` and store results with
[github-action-benchmark](https://github.com/benchmark-action/github-action-benchmark):

```yaml
name: Benchmark
on:
  push:
    branches:
      - master

permissions:
  contents: write
  deployments: write

jobs:
  benchmark:
    name: Run benchmark tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: appsup-dart/benchmark_test@v1
        with:
          paths: test/benchmarks_test.dart
          compile: jit,aot
          github-token: ${{ secrets.GITHUB_TOKEN }}
          comment-on-alert: true
          fail-on-alert: true
```

The action runs the benchmark CLI once per compile type, converts the JSONL
results to `github-action-benchmark` custom data, and commits benchmark history
to the `gh-pages` branch. Results are stored as `customBiggerIsBetter`, with
benchmark names suffixed by compile type, for example `parse json [jit]` and
`parse json [aot]`.

For Flutter packages, set `sdk` to `flutter` so the action installs Flutter and
runs `flutter pub get` before invoking the benchmark CLI:

```yaml
- uses: appsup-dart/benchmark_test@v1
  with:
    sdk: flutter
    flutter-channel: stable
    paths: test/benchmarks_test.dart
    compile: jit,aot
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

The benchmark CLI still runs VM benchmark tests through `dart test`, so the
benchmark file should be runnable on the Dart VM.


## Sponsor

If your team depends on this package in production, please consider sponsoring maintenance.

Sponsorship helps fund:
- compatibility and dependency updates
- bug fixes and issue triage
- documentation and migration support

👉 https://github.com/sponsors/rbellens
