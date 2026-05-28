
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

The CLI runs benchmarks with Dart assertions disabled by default so assertion
checks do not affect benchmark timings. Use `--enable-asserts` to opt back in
when you want assertion checks during a benchmark run:

```sh
dart run benchmark_test --enable-asserts test/benchmarks_test.dart
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

Filter benchmarks by name on the CLI:

```sh
dart run benchmark_test --name parse test/benchmarks_test.dart
dart run benchmark_test --plain-name "parse json" test/benchmarks_test.dart
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

`dart test` prints human-readable benchmark output. The `benchmark_test` CLI
supports `--output` to choose another format:

```sh
dart run benchmark_test --output benchmarkjs test/benchmarks_test.dart
dart run benchmark_test --output jsonl test/benchmarks_test.dart
```

Supported values:

* `human` — default, optimized for local development
* `benchmarkjs` — benchmark.js-compatible output for tools like `github-action-benchmark`
* `jsonl` — one JSON object per benchmark result (`ndjson` is accepted as an alias)

`ndjson` output uses this schema:

```json
{"formatVersion":1,"name":"my benchmarks parse json","throughput":{"value":12345.67,"unit":"ops/sec"},"statistics":{"relativeMarginOfError":2.34,"samples":42},"latency":{"mean":81,"unit":"microseconds"}}
```

#### Baselines

Human output compares each benchmark against the baseline stored in `build/benchmark_test/baselines.json`. Baselines are read-only by default:

```sh
dart test test/benchmarks_test.dart
```

Create or overwrite the baseline with the benchmark CLI:

```sh
dart run benchmark_test --update-baseline test/benchmarks_test.dart
```

The comparison uses throughput, so higher `ops/sec` is an improvement and lower `ops/sec` is a regression. Changes of at least 5% are marked with `✅` for improvements or `⚠️` for regressions. Improvements and regressions are colored when ANSI colors are supported.

#### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `minDuration` | `Duration(seconds: 2)` | Keep running measured iterations until at least this much measured time has elapsed |
| `minSamples` | `5` | Keep running measured iterations until at least this many measured iterations have completed |
| `warmupMinSamples` | `1` | Run at least this many warm-up iterations before sampling |
| `warmupMinDuration` | `Duration.zero` | Keep warming up until at least this duration has elapsed |
| `targetRme` | `null` | Optional precision target (`±%` margin of error). Sampling continues until this threshold is reached after minimums |
| `maxSamples` | `null` | Optional safety cap for measured iterations (use with `targetRme`) |
| `timeout` | `minDuration * 2` | Fail the test if it exceeds this duration |

Warm-up iterations are excluded from the reported statistics (`ops/sec`, margin of error, sampled runs, and average duration).

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

### Run benchmarks from VS Code

The default **Run** code lens uses `dart test`, which runs with Dart assertions
enabled. That can skew benchmark timings. Add the configurations below to get
extra code lenses that run through `benchmark_test` instead, so benchmarks are
**assert-free** (and JIT-only in this example).

```json
[
  {
    "name": "Run benchmark",
    "request": "launch",
    "type": "dart",
    "codeLens": {
      "for": ["run-test"]
    },
    "customTool": "dart",
    "customToolReplacesArgs": 5,
    "toolArgs": ["run", "benchmark_test", "--compiler", "jit"]
  },
  {
    "name": "Update baseline",
    "request": "launch",
    "type": "dart",
    "codeLens": {
      "for": ["run-test"]
    },
    "customTool": "dart",
    "customToolReplacesArgs": 5,
    "toolArgs": ["run", "benchmark_test", "--compiler", "jit", "--update-baseline"]
  }
]
```

Use `"for": ["run-test"]` only (not `debug-test`). The `benchmark_test` CLI
runs benchmarks in a separate VM with assertions disabled (JIT only here via
`--compiler jit`). Debug/VM-service flags are not used.

`customToolReplacesArgs: 5` removes the default `dart test` tool arguments so
`toolArgs` can invoke `dart run benchmark_test` instead. 

**Run benchmark** and **Update baseline** both use the assert-free runner; they
differ only in whether baselines are updated. **Run benchmark** compares against
existing baselines. **Update baseline** passes `--update-baseline` so results are
written to `build/benchmark_test/baselines.json`.


### Profile from the CLI

Run benchmarks under the CPU sampler with VM service attached (JIT only):

```sh
dart run benchmark_test --profile --compile jit test/benchmarks_test.dart
```

The CLI starts a separate VM in benchmark profile mode, connects over VM service,
records CPU samples between each benchmark's start and end pauses, and writes two
files per benchmark under `build/benchmark_test/profiles/`:

* `*.cpu.json` — VM service `CpuSamples` filtered to measured benchmark-body
  iterations (hooks and warm-up excluded)
* `*.devtools.json` — full DevTools snapshot of the captured profiling window
  (includes setup / teardown / warm-up). Stack frames
  include `packageUri` values (`dart:` for SDK libraries, empty for native code)
  so the flame chart uses the same colors as a live DevTools session.
* `*.postprocessed.devtools.json` — postprocessed DevTools snapshot with async
  runtime wrappers collapsed, benchmark body promoted as top frame, and measured
  benchmark-body samples only.

Samples are filtered to measured benchmark-body iterations (`setUpEach` /
`tearDownEach` and warm-up samples are excluded) so profiles focus on
benchmarked code.

To review a saved profile, open DevTools → **CPU Profiler** → **Import** and
choose a `*.devtools.json` file (the same format as DevTools **Export**).

Use `--name` or `--plain-name` to profile a single benchmark.

### Profile from VS Code

To profile from VS Code, launch the `benchmark_test` CLI directly:

```json
{
  "name": "Profile",
  "request": "launch",
  "type": "dart",
  "codeLens": {
    "for": ["run-test"]
  },
  "customTool": "dart",
  "customToolReplacesArgs": 5,
  "toolArgs": ["run", "benchmark_test", "--compiler", "jit", "--profile"]
}
```

This runs the same CLI profiling flow as terminal usage and writes profile files
to `build/benchmark_test/profiles/` (`*.cpu.json` and `*.devtools.json`). Import
the `*.devtools.json` files in DevTools → **CPU Profiler** → **Import**.

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
      - uses: appsup-dart/benchmark_test@action-v1
        with:
          paths: test/benchmarks_test.dart
          compile: jit,aot
          github-token: ${{ secrets.GITHUB_TOKEN }}
          comment-on-alert: true
          fail-on-alert: true
```

The `uses: ...@action-v1` ref selects the GitHub Action wrapper (`action.yml`
and helper scripts). The benchmark CLI and library version come from your
project's `benchmark_test` dev dependency in `pubspec.yaml`.

The action runs the benchmark CLI once per compile type, converts the JSONL
results to `github-action-benchmark` custom data, and commits benchmark history
to the `gh-pages` branch. Results are stored as `customBiggerIsBetter`, with
benchmark names suffixed by compile type, for example `parse json [jit]` and
`parse json [aot]`. The action always runs with Dart assertions disabled to keep
CI benchmark numbers representative.

For Flutter packages, set `sdk` to `flutter` so the action installs Flutter and
runs `flutter pub get` before invoking the benchmark CLI:

```yaml
- uses: appsup-dart/benchmark_test@action-v1
  with:
    sdk: flutter
    flutter-channel: stable
    paths: test/benchmarks_test.dart
    compile: jit,aot
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

The benchmark CLI still runs VM benchmark tests, so the benchmark file should be
runnable on the Dart VM.


## Sponsor

If your team depends on this package in production, please consider sponsoring maintenance.

Sponsorship helps fund:
- compatibility and dependency updates
- bug fixes and issue triage
- documentation and migration support

👉 https://github.com/sponsors/rbellens
