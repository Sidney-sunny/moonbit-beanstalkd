# MoonBit Beanstalkd Client

A binary-safe MoonBit Beanstalkd client with Node.js TCP transport and portable protocol/session packages.

## Protocol Responsibilities

The `protocol/` package encodes typed commands and decodes server replies without converting job bodies to text. NUL, CRLF, and non-UTF-8 bytes remain unchanged. Job identifiers use `UInt64`; numeric command arguments are checked before encoding.

Decoding accepts fragmented input and enforces limits on response headers, declared bodies, and retained data. Malformed framing, invalid integers, and resource limits produce structured errors. Statistics and tube lists support the YAML subset defined by Beanstalkd, rather than a general YAML parser.

The protocol package contains no socket access, queue server, scheduler, or automatic job replay. It runs on the JavaScript and wasm-gc targets.

## Ordered Sessions

The `client/` package matches one command with its expected response at a time, tracks the selected tube and watched-tube count, and rejects concurrent or unsolicited exchanges. Invalid framing or a mismatched reply invalidates the session. Transport adapters explicitly invalidate a session after an uncertain exchange; jobs are never replayed automatically.

## Node.js Client

`node_tcp/` supplies a socket boundary with an absolute request deadline, cancellation, backpressure handling, and connection invalidation. `node_client/` combines it with the portable session and exposes typed job, tube, statistics, and inspection operations. Socket-dependent packages target JavaScript; portable protocol and session packages also target wasm-gc.

The lifecycle example connects to pinned Beanstalkd 1.13 and checks binary submission, reservation, touch, release, bury, peek, kick, deletion, and tube cleanup. The server runner verifies its source checksum, refuses occupied ports, limits execution time, and stops only its own server process.

## Build and Test

Use the MoonBit versions recorded in `toolchain.json`.

```sh
moon fmt --check
moon check --target js --deny-warn
node scripts/with-beanstalkd.mjs -- moon test --target js --deny-warn
moon check --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
```

The protocol tests check literal command/reply records, binary payloads, integer boundaries, every single decoder split point, byte-at-a-time input, and malformed or oversized responses. Tests adapted from the pinned Go client provide an independent reference.

Run the socket bridge and runner checks, then the lifecycle example:

```sh
node --test node_tcp/bridge_test.mjs scripts/runner_test.mjs
node scripts/with-beanstalkd.mjs -- moon run examples/lifecycle --target js
```

Building the pinned server requires `make`, a C compiler, and `tar`. On Windows the runner uses the existing Debian WSL distribution. Generated files stay under ignored `_build/`.

## Interoperability

[Go interoperability](interop/README.md) checks exact binary payloads and job IDs in both producer/consumer directions against a pinned independent client. Run `node scripts/with-beanstalkd.mjs -- node interop/run.mjs`.

## Application Scenarios

- [CSV import](scenarios/CSV_IMPORT.md): a separate producer and worker validate an allowlisted fixture and count rows in MoonBit
- [Delayed retry and quarantine](scenarios/RETRY_QUARANTINE.md): release with a delay, inspect server state, and explicitly recover an invalid job without executing it
- [Touch and TTR expiry](scenarios/TTR.md): extend a reservation, observe expiry through an independent connection, and verify ownership transfer

## Protocol Baseline

[Benchmark](benchmark/README.md) the local binary encoder and bounded decoder with `node benchmark/run.mjs`. This measures a single JS process, including allocation and validation; it makes no TCP throughput claim.

## Package Consumption

[Local archive verification](packaging/README.md) imports a fixed extracted package from a separate consumer workspace with no registry credentials. Run `node scripts/with-beanstalkd.mjs -- node scripts/downstream-consumer.mjs`.

## Full Verification

Run `node scripts/verify.mjs` for formatting, strict builds, tests, real-server scenarios, package consumption, and the protocol baseline. It requires the versions in `toolchain.json`, Go, and the server build prerequisites. The GitHub workflow runs these checks with pinned toolchains.

## Contributing

See [Repository Guidelines](AGENTS.md), [API](docs/API.md), [scope](docs/POSITIONING.md), [acceptance criteria](docs/ACCEPTANCE.md), and [verification](docs/VERIFICATION.md). [Research](docs/RESEARCH.md) records a dated search snapshot; it does not establish universal absence of other implementations.

## Specification and License

The implementation follows the [Beanstalkd 1.13 protocol](https://github.com/beanstalkd/beanstalkd/blob/v1.13/doc/protocol.txt). Adapted test records come from [go-beanstalk](https://github.com/beanstalkd/go-beanstalk/tree/52e4a01c453b3de42105389beb2374f256751064); their original MIT notice and provenance are preserved in [protocol/NOTICE](protocol/NOTICE).

This project is licensed under [MIT](LICENSE).
