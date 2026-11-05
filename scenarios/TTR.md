# Touch and TTR expiry

From the repository root, use pinned MoonBit/Node.js and the server-runner
prerequisites (WSL Debian, `make`, and a C compiler on Windows):

```powershell
node scripts/with-beanstalkd.mjs -- node scenarios/ttr.mjs
```

The MoonBit example opens two independent TCP connections watching a unique
tube. The owner publishes and reserves a binary job with a six-second TTR.
The observer cannot reserve it. After 3.5 seconds, the owner touches the job
and verifies that `stats-job` reports more remaining time than before touch.

After another three seconds, the original reservation window has passed.
The example checks the observable `reserved` state, zero timeout count, and
the observer's failed immediate reserve. It then stops touching. The observer
uses one-second reserve requests, each with a 2.5-second transport deadline,
within an eight-second observation window. It must receive the same ID and
exact bytes, with server counters `timeouts: 1` and `reserves: 2`.

The former owner's touch must return `NOT_FOUND`, proving ownership moved.
The observer deletes the job and verifies the queue is empty. Assertions allow
scheduling variation; they do not require expiry at an exact millisecond.
Actual hold and expiry observation times are printed. The run normally takes
10 seconds, with a 25-second process limit and 120-second build limit.

`fixtures/ttr.hex` is an original 14-byte NUL/CRLF/non-UTF8 fixture. Its decoded
SHA-256 is `75948f6703d75e2f405778460216ad89c9d7178b797c2ec2f0a89d5524c27fb8`,
verified by the runner. Expected output includes `"result": "ttr ok"`,
`"same_job_rereserved": true`, `"timeout_count": 1`, and `"queue_empty": true`.
