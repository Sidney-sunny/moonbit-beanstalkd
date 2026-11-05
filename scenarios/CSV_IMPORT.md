# CSV import scenario

From the repository root, run with the pinned MoonBit/Node.js toolchains and
the Beanstalkd runner prerequisites (WSL Debian, `make`, and a C compiler on
Windows):

```powershell
node scripts/with-beanstalkd.mjs -- node scenarios/csv-import.mjs
```

The runner creates a unique tube and starts two separate MoonBit processes.
The producer publishes one JSON job with `csv_path` set to
`scenarios/fixtures/import.csv` and `task_id` set to `csv-import-fixture-v1`.
The worker reserves that byte-identical job, validates the fixed path and
identifier, reads the allowlisted fixture, and parses/counts rows in MoonBit.
Node FFI supplies raw file text only. The worker deletes the job and requires
an immediate subsequent reserve to return `TIMED_OUT`.

Supported CSV is intentionally restricted: printable ASCII, LF line endings
including a final LF, exact `id,name,task` header, and exactly three nonempty,
unquoted fields per row. IDs are positive, unique decimal UInt64 values.
Quoted fields, embedded newlines, and general RFC 4180 CSV are unsupported.

The original fixture has three rows and SHA-256
`6aaad27f2821ed1ada0fff0bac27ad99aca2f6cc6ad4e9e90faa842ff9482b1b`.
The runner verifies this checksum, actual CSV bytes, task bytes, and decimal
job IDs. Expected output: `"result": "csv-import ok"`, `"rows": 3`,
`"separate_processes": true`, `"deleted": true`, `"queue_empty": true`.
Client processes have 20-second limits; the build has a 120-second limit.
