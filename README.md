# MoonBit Beanstalkd Client

A MoonBit Beanstalkd protocol and session library, with binary-safe job bodies, bounded decoding, and ordered request/reply exchanges.

## Protocol Responsibilities

The `protocol/` package encodes typed commands and decodes server replies without converting job bodies to text. NUL, CRLF, and non-UTF-8 bytes remain unchanged. Job identifiers use `UInt64`; numeric command arguments are checked before encoding.

Decoding accepts fragmented input and enforces limits on response headers, declared bodies, and retained data. Malformed framing, invalid integers, and resource limits produce structured errors. Statistics and tube lists support the YAML subset defined by Beanstalkd, rather than a general YAML parser.

The package contains no socket access, queue server, scheduler, or automatic job replay. It runs on the JavaScript and wasm-gc targets.

## Ordered Sessions

The `client/` package matches one command with its expected response at a time, tracks the selected tube and watched-tube count, and rejects concurrent or unsolicited exchanges. Invalid framing or a mismatched reply invalidates the session. Transport adapters explicitly invalidate a session after an uncertain exchange; jobs are never replayed automatically.

## Build and Test

Use the MoonBit versions recorded in `toolchain.json`.

```sh
moon fmt --check
moon check --target js --deny-warn
moon test --target js --deny-warn
moon check --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
```

The protocol tests check literal command/reply records, binary payloads, integer boundaries, every single decoder split point, byte-at-a-time input, and malformed or oversized responses. Tests adapted from the pinned Go client provide an independent reference.

## Specification and License

The implementation follows the [Beanstalkd 1.13 protocol](https://github.com/beanstalkd/beanstalkd/blob/v1.13/doc/protocol.txt). Adapted test records come from [go-beanstalk](https://github.com/beanstalkd/go-beanstalk/tree/52e4a01c453b3de42105389beb2374f256751064); their original MIT notice and provenance are preserved in [protocol/NOTICE](protocol/NOTICE).

This project is licensed under [MIT](LICENSE).
