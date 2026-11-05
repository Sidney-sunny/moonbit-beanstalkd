# Repository Guidelines

## Project Structure & Module Organization

`protocol/` handles binary framing and limited YAML; `client/` holds portable session state. `node_tcp/` supplies sockets; `node_client/` provides typed async APIs. Package-local `*_test.mbt` files hold tests. `examples/` contains programs, `scenarios/` holds application runners, and `interop/` contains the pinned Go peer. `packaging/` verifies archive consumption; `benchmark/` records protocol baselines.

`docs/POSITIONING.md` defines contribution boundaries, `docs/ACCEPTANCE.md` tracks functional coverage, and `docs/VERIFICATION.md` explains checks. `evidence/` retains research records. Generated artifacts belong in ignored `_build/`.

## Build, Test, and Development Commands

Use versions in `toolchain.json`. From the repository root:

- `moon fmt`: format source; use `moon fmt --check` for validation.
- `moon check --target js`: type-check JS-compatible packages.
- `moon build --target js`: compile the JS target.
- `moon test --target js`: execute MoonBit tests on JS.

Repeat check/build/test with `--target wasm-gc` for portable packages. `node scripts/verify.mjs` runs tests, server scenarios, interoperability, local package consumption, and benchmarks. It needs Go, `make`, a C compiler, and `tar`; Windows uses existing Debian WSL. Use `pnpm` for Node dependencies; none are required.

## Coding Style & Naming Conventions

For new MoonBit code, use two-space indentation, `snake_case` functions/files, and `PascalCase` types; let `moon fmt` enforce formatting. Keep protocol logic independent of sockets. Write documentation in English only; omit emojis.

## Testing Guidelines

Use MoonBit test blocks in `*_test.mbt`, or `*_wbtest.mbt` for internal access. JavaScript checks use Node's built-in test runner. No coverage percentage is set; follow `docs/ACCEPTANCE.md`.

Cover binary payloads, integer bounds, decoder splits, malformed input, limits, cancellation, and disconnects. Assert exact bytes and IDs against the independent Go client. Preserve upstream notices in `protocol/NOTICE`. Save the source revision, output, and per-run artifacts; earlier results do not verify later changes.

## Commit & Pull Request Guidelines

Use Conventional Commits with a specific summary, such as `fix(protocol): reject oversized reply bodies`. Keep each change focused and independently useful.

PRs should describe the change, link relevant issues and acceptance items, report executed checks or blockers, and update the relevant English documentation. Keep pending features and unexecuted tests explicitly labeled.

## Positioning and Protocol Safety

Focus contributions on the Beanstalkd protocol client. Keep comparisons factual. Allow one ordered request/reply sequence per connection; invalidate after uncertain framing or transport timeouts. Never automatically replay `put`; the server may already have accepted it.
