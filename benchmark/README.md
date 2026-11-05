# Local protocol benchmark

Run `node benchmark/run.mjs` from the repository root. It builds the MoonBit
`examples/benchmark` package in JS release mode, runs it with Node, and writes
`_build/benchmark.json`. No server, registry login, or package publication is used.

The default workload warms up 2,000 iterations, then measures 20,000 PUT
encodings and 20,000 whole-buffer RESERVED decodings separately. The 14-byte
fixture in `body.hex` includes NUL, CRLF, and non-UTF-8 bytes. Every decode creates
a new bounded decoder and checks the UInt64 job identifier and exact body.
Allocation and validation are included in the measurements; fixture construction
and warmup are excluded. A checksum keeps the measured results observable.

The result records exact tool versions, CPU/platform, fixture SHA-256, operation
counts, byte counts, elapsed milliseconds, nanoseconds per operation, and
operations per second. It is a local single-process protocol baseline, with no
TCP measurement or Go performance comparison. There are no performance gates.

Optional environment variables: `BEANSTALKD_BENCH_ITERATIONS` (1–100,000) and
`BEANSTALKD_BENCH_WARMUP` (0–20,000). Keep these values and the fixture hash when
comparing runs. The runner bounds build/execution subprocesses to 30 seconds.
