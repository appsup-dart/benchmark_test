## 0.1.1+2

 - **PERF**(benchmark): use compile-time platform iteration timers. ([69c40f98](https://github.com/appsup-dart/benchmark_test/commit/69c40f98d2d432e2873e8c32105567b6527f1452))
 - **DOCS**: use action-v1 tag in GitHub workflow examples. ([bab7be67](https://github.com/appsup-dart/benchmark_test/commit/bab7be67eaf942b06087d29f08f105ebf07b089e))

## 0.1.1+1

 - **FIX**(benchmark): measure iterations with Timeline.now again. ([018be329](https://github.com/appsup-dart/benchmark_test/commit/018be329c7a6788f6b9e231eafb3b6b57bfe0390))

## 0.1.1

- **FEAT**: add dedicated benchmark CLI with support for `jit`, `aot`, `js`, and `wasm` compile targets.
- **FEAT**: add baseline comparison and update workflows with compiler-aware baselines and output formats (`human`, `benchmarkjs`, `jsonl`).
- **FEAT**: add CLI CPU profiling with automated profile export and benchmark-body focused flame chart data.
- **FEAT**: improve benchmark sampling with warmup-aware measurements and optional precision-driven stopping.
- **FEAT**: improve developer/CI workflow with assert-free benchmark runs, a GitHub Action, and VS Code run configurations.

## 0.1.0

 - **REFACTOR**: set min sdk to 3 and upgrade lints dev dependency. ([fd6f8b2e](https://github.com/appsup-dart/benchmark_test/commit/fd6f8b2e5464e82d085bab44e35d0f50631a2ac6))
 - **DOCS**: extend readme with detailed usage section. ([8f1676ab](https://github.com/appsup-dart/benchmark_test/commit/8f1676ab757012b14face9c873d67fe004b3e547))


## 0.0.2

 - **REFACTOR**: support for test_api ^0.7.0. ([e221cc6c](https://github.com/appsup-dart/benchmark_test/commit/e221cc6c2c19fac0767c845235cb67da728b7591))

## 0.0.1

- Initial version.
