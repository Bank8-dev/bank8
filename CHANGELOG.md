# Changelog - bank8

## v0.3.0 - 2026-09-26

- **Platform re-sync (cert-bound M2M + DBX outbox + Registration v2)**:
  all 4 services migrated to the 2026-09-26 platform API -
  certificate-bound mTLS DCR (RFC 8705: `persist_cert_files`,
  `/mtls/oauth/token`, `platform_ca_path()`; `ClientKeys`/
  `private_key_jwt` deleted), the DBX producer path (per-service
  `{leaf}.outbox` + `{leaf}.audit_journal` in leaf schemas, role
  search_paths `{leaf}, bank8, public`, all `sentin8.bus_inbox` writes
  retired, `-audit` M2M grants for the shell journal pusher), and
  `Registration` v2 (`PgRole.database`/`cross_schema_grants`,
  `schemas` field dropped, worker scope vocabulary prefixed). Ledger
  stream family unified to `ledger`. Build 0 errors/0 warnings; 24
  test suites green; DDL validated on a scratch database with roles.
- **Documentation restructure (documents.md applied)**: per-unit
  README.md (§3 overview template) + DESIGN.md (§4.1 DDD with the §4.2
  diagram set) for all 4 services, 3 contract crates, and the SDK
  facade; implementation-complete catalogs (ledger 91 endpoints/44
  tables/30 events; payments 90/55/25 resource types; fdx 71
  routes/15 tables/16 events); full rustdoc on every bank8-owned
  public item; ~460 ticket/phase references purged from comments
  (Reference Rule: comments cite DESIGN.md only); single-backlog
  consolidation (per-unit BACKLOG.md files retired, open stories
  moved to the root BACKLOG.md); root README.md/DESIGN.md rewritten
  as the vertical overview/DDD; historical functional designs moved
  to `../old-docs/bank8/` and their references repointed.

## v0.2.2 - 2026-09-04

- **Rust test coverage hardening (TEST-1..4)**: Unique test count 510 → 594
  (+84), all green, zero new compiler warnings (baseline 54 pre-existing in
  payments/fdx unchanged). Ledger `modules.rs` - the money-math core with
  ~22 previously untested pure functions - now carries 64 unit tests
  covering all 14 built-in modules: creation/posting validators, tiered-rate
  selection (inclusive `min_balance` boundary), daily accrual rounding at
  0.01 precision, overdraft protection + sweep thresholds, fee/dormancy
  schedules, dispatcher short-circuit order, derived parameters (credit
  clamp, remaining term, redraw %), and product-type parameter schemas.
  Tests exposed and documented a `param_dec` quirk: parameters are parsed
  via `as_str()`, so integer JSON values silently fall back to defaults -
  string params are the calling convention. `payments-worker` (previously 0
  tests) gained 15: terminal-state idempotency predicate, event payload
  parsing, SSE data-line extraction (extracted as pure seams from
  `worker.rs`, behavior preserved), and `WorkerConfig::from_env` defaults +
  overrides with a poison-tolerant env-var mutex. Contract crates
  `ledger-contracts` and `fdx-contracts` gained serde roundtrip tests
  (5 tests) matching the existing `payments-contracts` suite. Root Makefile
  `test-rust` aggregate no longer swallows vertical test failures with
  `|| true`. Design: `old-docs/bank8/sentin8-bank8-ledger-technical-design.md` §8.6,
  `old-docs/bank8/sentin8-bank8-payments-technical-design.md` §8.5. Stories TEST-1..4.

## v0.2.1 - 2026-08-29

- **Native `Decimal` money handling**: Enabled sqlx's `rust_decimal` feature (workspace + service Cargo.toml) and utoipa's `decimal` feature. All monetary columns (`DECIMAL`/`NUMERIC`) now decode natively as `rust_decimal::Decimal` and bind `Decimal` values directly - every `amount::text`/`balance::text` read-cast and `$N::numeric`/`$N::text::numeric`/string-bind write-cast is removed (ledger balances/transactions/statements/posting instructions, payments payments/mandates, T140 `SUM` aggregate, card LVT accumulator which also drops its `::float8` cast). Response DTO money fields (`currentBalance`, `BalanceResponse.amount`, `TransactionResponse.amount`, `StatementResponse` balances, `PaymentResponse.amount`, `MandateResponse.amount_limit`) changed `String` → `Decimal` - serde still emits JSON strings and OpenAPI still types them `string`, so the wire format is unchanged for clients, Flutter apps, and E2E suites. Request DTOs keep string input and now parse once with a 400 on invalid amounts before any DB work. Design: `old-docs/bank8/sentin8-bank8-ledger-technical-design.md` §8.3/§8.3a, `old-docs/bank8/sentin8-bank8-payments-technical-design.md` §8.4. Stories 11.1.57, 11.2.213.
- **Mandate insert bug fix**: `POST /v1/mandates` had a broken INSERT (13 VALUES for 12 columns, 12 placeholders for 11 binds) that could never execute; now fixed with the native `Decimal` bind.

## v0.2.0 - 2026-08-13

- **Module-prefixed scopes**: All OAuth scopes renamed from `ledger:*`, `payments:*`, `fdx:*` to `bank8:ledger:*`, `bank8:payments:*`, `bank8:fdx:*` to prevent clashes across modules.
- **Dynamic admin scopes**: Vertical admin scopes declared in `vertical-registry.json` under `admin_scopes`, stored in `sentin8_vertical_admin_scopes` table during enrollment, and dynamically loaded by sys during org/env creation - platform never hardcodes bank8 scopes.
- **Bank8:Admin app**: New staff-only admin dashboard app (`apps/admin/`) with SSO via shared BFF session cookie domain. Manages ledger products, accounts, postings, payments rules, FDX providers, and consents.
- **Removed from Sentin8:Dash**: All bank8 feature pages, service clients, sidebar entries, router routes, scope selectors, and health checks removed from the platform dashboard - Dash is now a pure platform admin tool.
- **Backlog**: Added `apps/admin/BACKLOG.md` with 6-phase implementation plan.
- **Design doc**: Added `old-docs/bank8/sentin8-bank8-admin-app-technical-design.md` (18 sections, implemented).
- **Eteller design doc**: Updated all scope references to module-prefixed form.

## v0.1.0 - 2026-08-10

- Initial domain split from the monolithic sentin8 workspace.
- Contains: ledger, payments, payments-worker, fdx.
- Contains contracts: ledger-contracts, payments-contracts, fdx-contracts.
- Contains Flutter apps: ebank, efintech, eteller.
- Depends on sentin8 via relative path dependencies.