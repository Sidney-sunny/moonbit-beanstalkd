# Client API

[Project](../README.md) | [Verification](VERIFICATION.md)

## Runtime and Packages

The development module is `sideny-sunny/beanstalkd`; Mooncakes publication and independent registry installation remain pending. `protocol` and `client` support JS and wasm-gc. `node_tcp`, `node_client`, and the examples require the JS target and Node.js. The library does not invoke Go or PHP; the pinned Go client is an independent test peer only.

Use `moon.pkg` imports for `sideny-sunny/beanstalkd/node_client` and `sideny-sunny/beanstalkd/protocol`. Executables with `async fn main` also import `moonbitlang/core/async`. See the complete [lifecycle program](../examples/lifecycle/main.mbt).

```moonbit
async fn main {
  let client = @node_client.connect("127.0.0.1", 11300)
  defer client.close()
  let selected = client.execute(@protocol.Use("imports"))
  println(selected == @protocol.Using("imports"))
  let reply = client.execute(@protocol.Put(0U, 0U, 30U, b"csv\x00\r\n"))
  match reply {
    Inserted(id) => println(id)
    _ => fail("job was not inserted")
  }
}
```

## Command and Reply Coverage

The typed `Client` helpers avoid manual reply matching for common operations:

| Helper group | Return values |
| --- | --- |
| `put`, `reserve`, `release` | `PutOutcome`, `ReserveOutcome`, `ReleaseOutcome`; buried acceptance, timeout, deadline-soon, and not-found remain distinct |
| `delete`, `bury`, `touch`, `kick_job`; `kick` | Boolean for success/not-found; count for batch kick |
| `use_tube`, `watch`, `ignore_tube`, `list_tube_used`, `list_tubes`, `list_tubes_watched` | Selected name, watch count, explicit `NotIgnored`, or tube-name array |
| `peek`, `peek_ready`, `peek_delayed`, `peek_buried` | Optional `Job { id: UInt64, body: Bytes }`; `None` means not found |
| `stats`, `stats_job`, `stats_tube` | String maps, optional for job/tube not-found; required job ID or tube name is checked against the request |

Helpers retain a `timeout_ms` argument. `put` defaults to priority 0, delay 0, TTR 60 seconds; `reserve` defaults to a zero-second server wait. Complete server errors not represented as normal outcomes raise `OperationError::ServerRejected(status)`. Unsupported but fully framed YAML raises `InvalidDocument`; a missing or wrong correlated stats identity invalidates the connection. The low-level `execute` API remains available for exact command/reply access.

| Family | Commands |
| --- | --- |
| Tubes | `Use`, `Watch`, `Ignore`, `ListTubes`, `ListTubeUsed`, `ListTubesWatched` |
| Publish and receive | `Put(priority, delay, ttr, Bytes)`, `ReserveWithTimeout(seconds)` |
| Lifecycle | `Delete`, `Release`, `Bury`, `Kick`, `KickJob`, `Touch` |
| Inspection | `Peek`, `PeekReady`, `PeekDelayed`, `PeekBuried`, `Stats`, `StatsJob`, `StatsTube` |

Job IDs remain `UInt64`; priority/delay/TTR and reserve seconds use `UInt32`. Bodies are `Bytes`, never UTF-8 strings. Typed replies include `Inserted`, `Reserved`, `Found`, `Using`, `Watching`, `Kicked`, raw `Ok(Bytes)`, and `Status(ServerStatus)`. `Buried(id)` after `Put` means the server accepted a buried job, so do not replay it.

`parse_stats` returns a flat string map to avoid numeric precision loss. `parse_tubes` returns tube names. These parsers accept only the server's documented flat ASCII subset, rejecting nested YAML, aliases, escapes, and duplicate map keys; they are not general YAML parsers. Raw bytes remain available through `Ok(Bytes)`.

## Deadlines, Failures, and Ownership

`connect(host, port, timeout_ms=5000, max_body=1048576)` includes a bounded connect deadline. `Client::execute(command, timeout_ms=5000)` allows one request at a time, with one absolute deadline covering all writes and reads. A concurrent call raises `SessionFailure(Busy)` without cancelling the active call. Choose a request deadline longer than a nonzero server reserve timeout plus network margin.

A complete server `Status(TimedOut)` is a normal reply and preserves connection usability. A transport `TransportError("TIMEOUT", ...)`, cancellation, malformed/truncated reply, unexpected command/reply pairing, or unsolicited data invalidates the connection. `RequestError` reports local/session errors separately. `close()` is idempotent and cancels pending work. There is no implicit reconnection, publication replay, deduplication, or exactly-once guarantee.

The portable `Session` exposes `begin`, `feed`, `finish`, `invalidate`, and read-only state accessors for alternative transports. Internal mutable state is private. The default decoder limits are a 1,024-byte header, 1 MiB body, and 2 MiB buffer. The Node client sets its buffer to the body limit plus 1,026 bytes. Application limits do not change the server's configured job-size limit.
