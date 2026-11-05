# Project Positioning and Overlap Boundaries

[Project](../README.md) | [Acceptance](ACCEPTANCE.md)

The related-work snapshot below was researched on 2026-11-02; documentation maintenance does not refresh that search. It explains the library's scope and protocol differences.

## Precise Deliverable

A MoonBit-native **client library for the existing Beanstalkd server protocol**, with a Node.js TCP adapter. It lets MoonBit producers and consumers use an existing Beanstalkd deployment. An independent Go client supplies the bidirectional interoperability check; PHP interoperability has not been verified. The protocol implementation, byte handling, reply validation, and connection state belong to MoonBit; JavaScript supplies the Node socket boundary.

The project does not implement a queue server, a general task framework, a scheduler, a dashboard, or a Redis-backed queue. Application examples demonstrate protocol use; they are not a competing worker framework.

## Related Work and Functional Overlap

| Public project | Shared application needs | Existing protocol or architecture | This project's bounded contribution |
| --- | --- | --- | --- |
| [nexacodes/moontask](https://github.com/nexacodes/moontask) | Background jobs, production, consumption, retry | Task abstraction with memory and Redis backends | A client for an existing Beanstalkd deployment; no generic task runtime |
| [Metalymph/relay](https://github.com/Metalymph/relay) | Queue consumption, acknowledgement, delivery reliability | Pluggable queue framework; memory and Valkey/Redis adapters; NATS planned | Beanstalkd's wire protocol, tube state, and job lifecycle rather than a backend-neutral framework |
| [clhhhhhh/moon-nsq](https://github.com/clhhhhhh/moon-nsq) | TCP messaging, publish/consume, delayed delivery | NSQ TCP V2, topics, channels, discovery | Beanstalkd commands and replies, tubes, TTR, reserve/release/bury/kick semantics |
| [DDD12345-D/moon-amqp](https://github.com/DDD12345-D/moon-amqp/blob/master/README.mbt.md) | Broker integration, producers, consumers | RabbitMQ AMQP 0-9-1 frames, exchanges, channels | Beanstalkd text headers and binary bodies; no AMQP implementation |

These are real functional intersections. Different server names alone do not establish sufficient contribution. Reviewers should evaluate the implemented library, examples, failure handling, and independent interoperability evidence.

## Evidence Required for the Contribution

1. Byte-exact binary requests and bounded incremental replies, including NUL/CRLF payloads, UInt64 IDs, all split points, and invalid inputs.
2. A real TCP connection with deadlines, cancellation, short I/O, and connection invalidation after uncertain results; never silently replay `put`.
3. Observable ready/reserved/deleted, delayed/released, buried/kicked, and touch/TTR behavior on a pinned Beanstalkd server.
4. Go-to-MoonBit and MoonBit-to-Go interoperability against the independent pinned client, with reproducible commands and per-run results.
5. Documented API and runnable scenarios from the acceptance checklist. Pending work must remain labeled pending.

## Scope and Related-Work Evidence

Describe the project as a **MoonBit Beanstalkd protocol client with binary-safe decoding and cross-language interoperability**. Do not describe it as the first MoonBit message queue, a novel queue algorithm, or proof that nobody else is developing a similar project.

On 2026-11-02, checks of 3,520 [Mooncakes metadata records](https://mooncakes.io/api/v0/modules), GitHub repositories/code/issues, and public web results located no equivalent public MoonBit Beanstalkd client. Private, unindexed, and unpublished work remain outside this conclusion. Recheck the dated sources before relying on that result for a later comparison.

Reference the [pinned official protocol](https://github.com/beanstalkd/beanstalkd/blob/v1.13/doc/protocol.txt) and [Go reference client](https://github.com/beanstalkd/go-beanstalk/tree/52e4a01c453b3de42105389beb2374f256751064). Preserve licenses and provenance for adapted material. Use the [functional checklist](ACCEPTANCE.md) and [per-run verification](VERIFICATION.md) to distinguish implementation from executed evidence.
