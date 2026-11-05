# Delayed retry and quarantine

Run from the repository root with pinned MoonBit/Node.js and the server-runner
prerequisites (WSL Debian, `make`, and a C compiler on Windows):

```powershell
node scripts/with-beanstalkd.mjs -- node scenarios/retry-quarantine.mjs
```

The original `fixtures/retry.json` task intentionally fails its first simulated
application attempt. MoonBit releases the reserved job with a two-second delay,
observes `stats-job` state `delayed`, and verifies an immediate reserve returns
`TIMED_OUT`. It polls for at most eight seconds, verifies the same job ID and
exact payload, succeeds on the second attempt, and deletes it. Assertions use
observable server states rather than an exact scheduling boundary.

A separate `fixtures/quarantine.json` task fails validation before business
execution. MoonBit buries it, verifies `buried` state, peeks its unchanged bytes,
and proves a regular reserve cannot retrieve it. An explicit `kick-job` makes
it visible again. Controlled reprocessing rechecks the invalid payload and
deliberately deletes it without running business work. This is example policy,
not an automatic retry framework.

Fixture SHA-256 values, checked by the runner:

| Fixture | SHA-256 |
| --- | --- |
| `retry.json` | `a7efc2dbf67a5639cb729667f7677b4a52910dbebcc22fe196c14fffe56a223a` |
| `quarantine.json` | `f4ce833e25498335a3ca364a3e1691aef400d108ee2bde8c5ebde8a2e1b9ca7e` |

Expected output includes `retry-quarantine ok`, two attempts, zero invalid
executions, successful deletions, and `queue_empty: true`. The example process
is limited to 20 seconds; the build is limited to 120 seconds.
