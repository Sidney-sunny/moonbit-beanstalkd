# Go and MoonBit interoperability

Run from the repository root with the pinned MoonBit and Node.js toolchains,
Go 1.22 or newer, and the prerequisites in `scripts/with-beanstalkd.mjs`:

```powershell
node scripts/with-beanstalkd.mjs -- node interop/run.mjs
```

The server runner downloads, verifies, builds, starts, and stops the pinned
Beanstalkd release. On Windows, it requires WSL Debian with `make` and a C
compiler. For an existing server, set `BEANSTALKD_HOST` and `BEANSTALKD_PORT`,
then run `node interop/run.mjs` directly.

The runner builds the independent Go reference client and the MoonBit example.
Each direction uses a unique tube: Go publishes and MoonBit consumes, then
MoonBit publishes and Go consumes. Consumers compare exact bytes, touch and
delete the job, and require a zero-second reserve to report an empty queue.
Job IDs remain unsigned decimal strings in the comparison output.

Expected output includes `"result": "interop ok"`, both directions, matching
IDs per exchange, `"bytes": 14`, `"deleted": true`, and `"queue_empty": true`.
Each client process is limited to 15 seconds; builds have a 120-second limit.
The Go connection also sets an eight-second transport deadline.

`fixtures/binary-task.hex` stores the original NUL/CRLF/non-UTF8 fixture.
`provenance.json` records its decoded checksum and the exact Go client revision;
`go/go.sum` locks the reference dependency. Build output stays in `_build/`.
This checks binary protocol interoperability, not the complete planned three
application scenarios.
