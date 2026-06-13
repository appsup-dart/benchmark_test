
[![Ceasefire Now](https://badge.techforpalestine.org/default)](https://techforpalestine.org/learn-more)

[:heart: sponsor](https://github.com/sponsors/rbellens)

A tool to integrate benchmarking into your development and testing workflow.

**New to `benchmark_test`?** Read the walkthrough article [*From "I think this is slow" to "I know why": a practical Dart benchmark workflow*](https://medium.com/@rik.bellens_81452/from-i-think-this-is-slow-to-i-know-why-a-practical-dart-benchmark-workflow-ed5bd9db8caf) for the full loop — IDE setup, baselines, profiling, compile targets, and CI — with screenshots and examples. This README is the reference; the article is the guided tour.

## Features

* Benchmarks that look and run like `package:test` tests
* Dedicated CLI runner (assert-free by default, multiple compile targets)
* Local baselines with percentage comparison
* CPU profiling with DevTools export and optional postprocessing
* GitHub Action for trend charts and regression alerts

## Quick start

Add `benchmark_test` as a dev dependency:

```yaml
dev_dependencies:
  benchmark_test: ^0.1.1
```

Create a benchmark test file and use `benchmark()` like a test:

```dart
import 'package:benchmark_test/benchmark_test.dart';
import 'package:test/test.dart';

void main() {
  group('my benchmarks', () {
    benchmark('parse json', () {
      // code to benchmark
    });

    benchmark(
      'parse json (long run)',
      () {
        // code to benchmark
      },
      minDuration: Duration(seconds: 4),
      minSamples: 30,
    );
  });
}
```

Run with the package CLI (recommended for stable timings):

```sh
dart run benchmark_test test/benchmarks_test.dart
```

`dart test` also works and prints benchmark output, but runs with asserts enabled. See the [article](https://medium.com/@rik.bellens_81452/from-i-think-this-is-slow-to-i-know-why-a-practical-dart-benchmark-workflow-ed5bd9db8caf) for why that matters and how to wire VS Code code lenses.

## CLI

```sh
dart run benchmark_test [options] <test-files...> [-- dart-test-args...]
```

Common options:

| Option | Description |
|--------|-------------|
| `--compile`, `-c` | Compile type(s): `jit`, `aot`, `js`, `wasm`, or comma-separated (default: `jit`) |
| `--update-baseline` | Write results to `build/benchmark_test/baselines.json` |
| `--profile` | Capture CPU profiles (JIT only) |
| `--output` | `human` (default), `benchmarkjs`, or `jsonl` |
| `--name` | Filter benchmarks by regex |
| `--plain-name` | Filter benchmarks by plain name |
| `--enable-asserts` | Run with Dart asserts enabled |
| `--run-skipped` | Run skipped tests/benchmarks |

Examples:

```sh
dart run benchmark_test test/benchmarks_test.dart
dart run benchmark_test --compile jit,aot test/benchmarks_test.dart
dart run benchmark_test --update-baseline test/benchmarks_test.dart
dart run benchmark_test --profile --plain-name "parse json" test/benchmarks_test.dart
dart run benchmark_test --output jsonl test/benchmarks_test.dart
```

Run `dart run benchmark_test --help` for the full option list.

### Compile types

| Type | Runs as | Notes |
|------|---------|-------|
| `jit` | Dart VM (kernel) | Default; required for `--profile` |
| `aot` | Native executable (`dart compile exe`) | Production-like VM/server timing |
| `js` | JavaScript | Web targets |
| `wasm` | WebAssembly | Web targets |

Baselines are stored per compile type (for example `jit::my benchmarks parse json`).

## `benchmark()` API

`benchmark()` registers a test that repeatedly executes the given function and prints statistics:

```text
Benchmark: my benchmarks parse json
  12345.67 ops/sec
  ±2.34% margin of error
  42 runs sampled
  0:00:00.000081 average duration
```

| Field | Meaning |
|-------|---------|
| **ops/sec** | Estimated operations per second |
| **±%** | Relative margin of error (95% confidence interval) |
| **runs sampled** | Measured iterations (after warm-up) |
| **average duration** | Mean time per iteration |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `minDuration` | `Duration(seconds: 2)` | Keep sampling until at least this much measured time has elapsed |
| `minSamples` | `5` | Keep sampling until at least this many measured iterations have completed |
| `warmupMinSamples` | `1` | Warm-up iterations before sampling |
| `warmupMinDuration` | `Duration.zero` | Minimum warm-up duration |
| `targetRme` | `null` | Stop when relative margin of error is at most this value (after minimums) |
| `maxSamples` | `null` | Upper cap on measured iterations (use with `targetRme`) |
| `timeout` | `minDuration * 2` | Fail if sampling exceeds this duration |

Warm-up iterations are excluded from reported statistics.

### `setUpEach` and `tearDownEach`

Run before and after every measured iteration (not timed). Standard `setUp`, `tearDown`, `setUpAll`, and `tearDownAll` from `package:test` also apply.

```dart
group('with setup', () {
  setUpEach(() {
    // runs before each measured iteration
  });

  tearDownEach(() {
    // runs after each measured iteration
  });

  benchmark('my benchmark', () {
    // ...
  });
});
```

In nested `group`s, `setUpEach` / `tearDownEach` apply only to benchmarks in that group.

## Baselines

Human output compares against `build/benchmark_test/baselines.json`:

```sh
dart run benchmark_test --update-baseline test/benchmarks_test.dart
dart run benchmark_test test/benchmarks_test.dart
```

Higher `ops/sec` is an improvement. Changes of at least **5%** are marked with `✅` (improvement) or `⚠️` (regression). Smaller changes show as plain text with `(within ±5% threshold)`.

The file lives under `build/` (gitignored by default). See the [article](https://medium.com/@rik.bellens_81452/from-i-think-this-is-slow-to-i-know-why-a-practical-dart-benchmark-workflow-ed5bd9db8caf) for a worked optimization example.

## Output formats

The CLI supports `--output`:

| Format | Use |
|--------|-----|
| `human` | Local development (default) |
| `benchmarkjs` | [github-action-benchmark](https://github.com/benchmark-action/github-action-benchmark) compatible |
| `jsonl` | One JSON object per result (`ndjson` alias accepted) |

JSONL schema:

```json
{"formatVersion":1,"name":"my benchmarks parse json","compiler":"jit","throughput":{"value":12345.67,"unit":"ops/sec"},"statistics":{"relativeMarginOfError":2.34,"samples":42},"latency":{"mean":81,"unit":"microseconds"}}
```

## VS Code

The default **Run** code lens uses `dart test` (asserts on). Add custom code lenses that invoke the `benchmark_test` CLI instead. Use `"for": ["run-test"]` only, not `debug-test`.

Restrict lenses to benchmark files with `codeLens.path` — filename globs must start with `**/` (for example `"**/*_benchmark_test.dart"`).

```json
{
  "configurations": [
    {
      "name": "Run benchmark",
      "request": "launch",
      "type": "dart",
      "codeLens": {
        "for": ["run-test"],
        "path": "**/*_benchmark_test.dart"
      },
      "customTool": "dart",
      "customToolReplacesArgs": 5,
      "toolArgs": ["run", "benchmark_test"]
    },
    {
      "name": "Update baseline",
      "request": "launch",
      "type": "dart",
      "codeLens": { "for": ["run-test"] },
      "customTool": "dart",
      "customToolReplacesArgs": 5,
      "toolArgs": ["run", "benchmark_test", "--update-baseline"]
    },
    {
      "name": "Profile benchmark",
      "request": "launch",
      "type": "dart",
      "codeLens": { "for": ["run-test"] },
      "customTool": "dart",
      "customToolReplacesArgs": 5,
      "toolArgs": ["run", "benchmark_test", "--profile"]
    }
  ]
}
```

`customToolReplacesArgs: 5` removes the default `dart test` arguments so `toolArgs` can run `dart run benchmark_test`. The [article](https://medium.com/@rik.bellens_81452/from-i-think-this-is-slow-to-i-know-why-a-practical-dart-benchmark-workflow-ed5bd9db8caf) shows what these lenses look like in the editor.

## Profiling

JIT only:

```sh
dart run benchmark_test --profile --plain-name "parse json" test/benchmarks_test.dart
```

Writes under `build/benchmark_test/profiles/` per benchmark:

| File | Description |
|------|-------------|
| `*.cpu.json` | Raw VM `CpuSamples`, filtered to measured benchmark-body iterations |
| `*.devtools.json` | DevTools snapshot (import or drag into **CPU Profiler**) |
| `*.postprocessed.devtools.json` | Same format, postprocessed by the package — async wrappers collapsed, setup/warm-up stripped, benchmark body promoted |

The postprocessed file is an extra step the package adds; a normal DevTools export looks like the unprocessed snapshot. The [article](https://medium.com/@rik.bellens_81452/from-i-think-this-is-slow-to-i-know-why-a-practical-dart-benchmark-workflow-ed5bd9db8caf) compares both with flame chart screenshots.

## GitHub Action

Add `.github/workflows/benchmark.yaml`:

```yaml
name: Benchmark
on:
  push:
    branches: [master]

permissions:
  contents: write
  deployments: write

jobs:
  benchmark:
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

The `@action-v1` ref selects the action wrapper; the CLI version comes from your project's `benchmark_test` dev dependency.

Key inputs: `paths`, `compile` (action default `jit,aot`), `github-token`, `fail-on-alert`, `comment-on-alert`. Also `working-directory`, `sdk` / `flutter-channel` (Flutter), `dart-test-args`, `benchmark-data-dir-path` (default `dev/bench`), `gh-pages-branch`, `alert-threshold`, `auto-push`. See [`action.yml`](action.yml).

Results are published to GitHub Pages with one chart per benchmark; each compile type is a separate series (for example `parse json [jit]`). Live dashboard example: [appsup-dart.github.io/firebase_dart/dev/bench/](https://appsup-dart.github.io/firebase_dart/dev/bench/).

For Flutter packages:

```yaml
- uses: appsup-dart/benchmark_test@action-v1
  with:
    sdk: flutter
    flutter-channel: stable
    paths: test/benchmarks_test.dart
    compile: jit,aot
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

Benchmark files must be runnable on the Dart VM. See the [article](https://medium.com/@rik.bellens_81452/from-i-think-this-is-slow-to-i-know-why-a-practical-dart-benchmark-workflow-ed5bd9db8caf) for setup steps and what the dashboard tells you.

## Sponsor

If your team depends on this package in production, please consider sponsoring maintenance.

Sponsorship helps fund:

- compatibility and dependency updates
- bug fixes and issue triage
- documentation and migration support

👉 https://github.com/sponsors/rbellens
