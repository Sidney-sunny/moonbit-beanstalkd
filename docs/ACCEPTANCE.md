# Acceptance Criteria

[Project](../README.md) | [Positioning](POSITIONING.md) | [Verification](VERIFICATION.md)

Checked implementation items identify capabilities or checks present in the source. They do not assert that an arbitrary revision passed. Execution and release checks require evidence for the reviewed commit, as described in [verification](VERIFICATION.md).

## Implemented Protocol and Runtime Scope

- [x] Pin MoonBit, Node.js, Go, and the Beanstalkd source release/checksum; provide bounded local-server and CI runners.
- [x] Separate portable protocol/session packages for JS and wasm-gc from Node.js-only sockets and async APIs.
- [x] Encode and decode use/watch/ignore, put, reserve-with-timeout, delete/release/bury/kick/kick-job/touch/peek, and stats/list families; document exact variants in the [API](API.md).
- [x] Preserve binary bodies, NUL/CRLF, UInt64 IDs, and unsigned 32-bit priority/delay/TTR without text conversion or narrowing.
- [x] Bound incremental decoding and validate CRLF, lengths, integers, expected replies, and configured resource limits.
- [x] Distinguish server states from protocol/transport failures; serialize exchanges and invalidate uncertain connections without automatic publication replay.
- [x] Parse the documented flat stats/list YAML subset without claiming general YAML support.

## Independent and Application Checks

- [x] Adapt pinned Go transcript cases with MIT provenance in [protocol/NOTICE](../protocol/NOTICE), rather than relying only on self-generated round trips.
- [x] Provide bidirectional Go/MoonBit producer/consumer checks comparing exact binary bytes and IDs; PHP interoperability is not a verified deliverable.
- [x] Provide real-server lifecycle and touch/TTR ownership checks with observable states, bounded waits, and queue cleanup assertions.
- [x] Provide [CSV import](../scenarios/CSV_IMPORT.md) with separate processes, fixed input, exact task bytes, row count, deletion, and empty-queue assertions.
- [x] Provide [retry/quarantine](../scenarios/RETRY_QUARANTINE.md) with delayed release, later success, separately buried invalid input, inspection, kick, and controlled reprocessing.
- [x] Provide an [isolated local archive consumer](../packaging/README.md) and a [reproducible protocol baseline](../benchmark/README.md); neither claims registry installation or Go performance parity.

## Execution Gates for the Reviewed Commit

- [ ] Preserve a complete local verification record with exact source revision, tool versions, commands, exit codes, test counts, and scenario output.
- [ ] Confirm formatting and JS/wasm-gc check/build/test; keep socket-dependent packages JS-only.
- [ ] Confirm lifecycle, independent Go interoperability, application scenarios, archive consumption, and bounded server cleanup on the reviewed source.
- [ ] Confirm hosted CI conclusion and artifacts for the exact pushed commit; workflow configuration alone does not satisfy this gate.
- [ ] Close the remaining fault-injection coverage: short reads/writes, mid-body disconnects, truncated replies, cancellation, bounded completion, and correct connection disposition. Map each subcondition to a concrete test before marking the whole gate complete.

Controlled socket tests cover several failure cases, but passing one peer script does not establish every real-server or end-to-end fault condition. Test counts from different targets may repeat the same portable cases.

## Package Distribution

- [ ] Distribute the package with its MIT license and upstream notices.
- [ ] Install the released version from Mooncakes in an independent consumer and run the documented producer/worker behavior; local ZIP consumption is insufficient.

Mooncakes publication and independent registry installation remain unverified. Keep unexecuted checks and unresolved subconditions pending even when related source or examples already exist.
