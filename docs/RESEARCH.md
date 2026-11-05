# Historical Research and Duplication Audit

[Project](../README.md) | [Evidence JSON](../evidence/recheck.json)

Audit date: 2026-11-01, Asia/Shanghai. This is a historical initiation-stage snapshot, not the implementation or release status of a later revision. No new search is implied by documentation maintenance. For implementation scope and execution evidence, see [positioning](POSITIONING.md) and [verification](VERIFICATION.md).

The full registry response originally named `mooncakes_modules_2026-11-01.json` is not included in this repository. The committed JSON records summarized observations and search parameters, not a reproducible copy of that complete registry response. Neither this audit nor zero search hits proves universal absence.

## Search coverage and results

| Source | Query or method | Observed result |
| --- | --- | --- |
| [Mooncakes full metadata API](https://mooncakes.io/api/v0/modules) | Read all 3,518 module records; names, descriptions and keywords matched against beanstalk / beanstalkd / tube queue | No corresponding module found |
| GitHub public repository search API | `beanstalk language:MoonBit`, `beanstalk moonbit`, `beanstalkd moonbit`, `"work queue" language:MoonBit` | Each returned zero repositories |
| GitHub code search via connector | `beanstalkd language:MoonBit`, `"reserve-with-timeout" language:MoonBit`, `"beanstalkd" extension:mbt` | Each returned zero code results |
| GitHub code search and source inspection | `beanstalk language:MoonBit` | One result: AWS Elastic Beanstalk domain entries in [MoonbitHTTP public suffix data](https://github.com/ZSeanYves/MoonbitHTTP/blob/0967034f11983b5a53f1843470c21ecc6512a4a7/policy/cookie/psl_data.mbt), not a queue client |
| Web search | Exact Beanstalkd/MoonBit combinations; moon.mod, mbt and Mooncakes aliases | No equivalent client located; unrelated package lists and AWS names excluded |

GitHub code indexing omitted some other known MoonBit libraries during this audit. A zero result alone is therefore insufficient. The conclusion relies on the registry, repository search, aliases and direct source inspection together. Private/unpublished repositories are outside scope. Repeat the check before relying on it for a later comparison.

## Mature upstream and adoption

| Evidence | What it establishes |
| --- | --- |
| [Official protocol](https://github.com/beanstalkd/beanstalkd/blob/master/doc/protocol.txt) | Defined commands, binary bodies, tube semantics, error cases and task lifecycle |
| [Go client at 52e4a01](https://github.com/beanstalkd/go-beanstalk/tree/52e4a01c453b3de42105389beb2374f256751064) | Existing producer/consumer API and MIT implementation reference |
| [Reference conn_test.go](https://github.com/beanstalkd/go-beanstalk/blob/52e4a01c453b3de42105389beb2374f256751064/conn_test.go) | Reusable request/response transcript concepts for use/watch/ignore/reserve/delete/release/bury/peek/stats/touch |
| [Laravel 12 queue drivers](https://laravel.com/docs/12.x/queues) | A mature application framework already integrates this queue backend |
| [Pheanstalk registry record](https://packagist.org/packages/pda/pheanstalk) and [JSON API](https://packagist.org/packages/pda/pheanstalk.json) | Mature client adoption; API snapshot reported 35,463,810 total installs and 680,207 monthly installs. These are package install events, not unique users or predicted MoonBit demand |

The Go reference's [License](https://github.com/beanstalkd/go-beanstalk/blob/52e4a01c453b3de42105389beb2374f256751064/License) is MIT. Adapted code or fixtures must retain its notice. At the audit date, pinning a concrete Beanstalkd release and checksum was a future implementation gate; the project was documentation-only. Later source pins are documented in [verification](VERIFICATION.md).

## Why this is a project rather than a thin wrapper

The proposed contribution combined binary-safe framing, incremental bounded decoding, ordered command processing, job/tube state, a real transport adapter and reference-client interoperability. A text encoder alone would not meet that planned engineering scope.

The nearest generic queue clients solve different server protocols and are not wire-compatible. This audit does not claim that general queueing infrastructure is absent from MoonBit.

## Decision and remaining uncertainty

The initiation recommendation was an independent Beanstalkd client, conditional on a day-one TCP/toolchain gate. The original estimate was 48–72 developer hours; it is not a remaining-effort estimate. At the audit date, no direct demand from a specific MoonBit user had been documented. Upstream adoption did not establish guaranteed usage in this ecosystem.

Use this dated record as research context; consult the source and version-specific verification for the library's implemented behavior.
