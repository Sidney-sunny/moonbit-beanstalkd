# Verification and Reproduction

[Project](../README.md) | [API](API.md) | [Acceptance](ACCEPTANCE.md)

## Evidence Applies to One Revision

Verification results belong to the exact source revision and command that produced them. This page describes the checks and their evidence; it does not claim that a new revision passed because an earlier local run or hosted job succeeded.

Record `git rev-parse HEAD`, the working-tree status, and the terminal or CI log with each run. A run with uncommitted changes must identify them. Component-only snapshots establish only the checks and files included in that snapshot.

## Run the Checks

Use the versions in [toolchain.json](../toolchain.json). Full verification requires Go, `tar`, `make`, and a C compiler. On Windows, the server runner uses an existing Debian WSL distribution. No Node dependencies need installation.

```sh
node scripts/verify.mjs
```

The runner checks tool versions, then runs formatting, JS and wasm-gc check/build/test with warnings denied, Node TCP and server-runner tests, the lifecycle example, Go interoperability, application scenarios, local package consumption, and the protocol benchmark. If a prerequisite or check fails, the full run is incomplete; execute individual checks for diagnosis without reporting full-suite success.

| Check group | Behavior examined |
| --- | --- |
| Portable protocol and session | Literal bytes, integer bounds, decoder splits, malformed replies, resource limits, correlation, and ordered state |
| Node TCP and async client | Fragmented loopback traffic, deadlines, cancellation, backpressure, connection invalidation, and typed helpers |
| Server runner | Occupied-port rejection, bounded execution, and cleanup of its own server |
| Pinned-server programs | Lifecycle, CSV import, retry/quarantine, touch/TTR ownership, and bidirectional Go interoperability |
| Package consumer | Actual local ZIP contents and a separate consumer module; not a Mooncakes registry install |
| Protocol benchmark | Dataset hash, warmup, operation counts, exact tool versions, and local encoding/decoding measurements |

Individual commands and expected outputs are documented for [CSV](../scenarios/CSV_IMPORT.md), [retry/quarantine](../scenarios/RETRY_QUARANTINE.md), [TTR](../scenarios/TTR.md), [Go interoperability](../interop/README.md), [local archive consumption](../packaging/README.md), and the [benchmark](../benchmark/README.md). For the basic lifecycle:

```sh
node scripts/with-beanstalkd.mjs -- moon run examples/lifecycle --target js
```

## Read the Results

| Artifact | Contents |
| --- | --- |
| `_build/verification.json` | Required and observed tool versions, command exit codes, durations, and overall completion |
| `_build/downstream/result.json` | Package archive hash, content checks, consumer results, and explicit registry/publication flags |
| `_build/benchmark.json` | Fixture hash, workload, platform, tool versions, and measurements |

A successful full run requires `complete: true`, every recorded command exiting with code zero, and the corresponding assertions in the saved log. The verification JSON does not replace the source revision or test-output log. Preserve artifacts before rerunning because their default paths are overwritten. Report actual test counts from that run; JS and wasm-gc repeat the portable cases and must not be summed as independent cases.

The [CI workflow](../.github/workflows/ci.yml) is configured to archive these artifacts. Confirm the exact commit, conclusion, and available artifacts in the [hosted runs](https://github.com/Sidney-sunny/moonbit-beanstalkd/actions) before claiming hosted success. A workflow file or an artifact from another revision is not that evidence.

## Pinned Inputs and Limits

The [server pin](../scripts/beanstalkd-source.json) selects Beanstalkd 1.13 and its source archive checksum. The [Go reference pin](../interop/provenance.json) selects commit `52e4a01c453b3de42105389beb2374f256751064`, resolved as `v0.2.0`, with locked Go sums and the original binary fixture hash. Adapted transcript cases retain their MIT notice in [protocol/NOTICE](../protocol/NOTICE).

Controlled socket peers exercise transport faults; application programs use the pinned server. These are distinct forms of evidence. TTR checks use observable ownership/state and bounded waits with margins, not an exact scheduling instant. The [acceptance checklist](ACCEPTANCE.md) retains unverified fault-injection subconditions.

Mooncakes publication and independent registry installation remain unverified. Local ZIP consumption establishes a separate boundary. CSV is an example-specific subset; protocol benchmarks include allocation/validation and establish neither TCP throughput nor parity with Go. Node.js supplies sockets; wasm-gc covers portable protocol/session logic. No TLS, pool, failover, automatic replay, or production-readiness claim is made.
