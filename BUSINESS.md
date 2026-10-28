# bank8 - Business Requirements & Functionality

> Secure Post-Quantum-Safe Core Banking, ISO 20022 Payments Secure Post-Quantum-Safe Core Banking & ISO 20022 Payment Platform That Heals and Scales Itself. Open Banking Platform That Heals and Scales Itself.

> Audience: product owners, business analysts, and anyone evaluating what the
> bank8 vertical **does for the business**. For the overview read `README.md`;
> for wire-level detail read `DESIGN.md`. Per-unit BRDs live beside each
> service and app (`services/*/BUSINESS.md`, `apps/*/BUSINESS.md`) - this
> document is the vertical rollup; per-unit docs state the functionality, this
> one states the business.

---

## 1. Business Purpose

- **A complete retail bank on platform rails** - deposit and lending accounts,
  card issuing, domestic and cross-border payments, and FDX v6.5 open banking
  delivered as one installable vertical, composed entirely on Sentin8
  platform services (identity, events, workflows, scheduling, storage).
- **Provable money invariants** - double-entry atomicity, idempotent money
  movement, immutable terminal states, and tenant isolation on every row are
  enforced by the platform's data plane, not by app conventions.
- **Consent-first data sharing** - customer financial data leaves the bank
  only under an explicit, revocable consent, with field-level minimization
  applied structurally before serialization.
- **Delegated counter banking** - branch staff operate on customer accounts
  through customer-approved, time-boxed, audited delegation instead of
  credential sharing.
- **Zero per-vertical infrastructure** - the vertical ships banking logic
  only; every cross-cutting concern is inherited from the platform, so a new
  tenant gets the full stack by enabling three services in an environment.

## 2. Business Scope (What the Vertical Provides)

| # | Capability block | What the business gets | Delivered by |
|---|---|---|---|
| 1 | Core banking | Customer registry; customer + internal accounts; 13 product types as configurable data; double-entry postings; 3-D balances; scheduled jobs; statements; checksum-chained journal | Bank8:Ledger |
| 2 | Payment orchestration | Instructions, scheme flows (B8 on-us, SEPA, TIPS, SWIFT AGI on ISO 20022), card issuing/lifecycle/3DS, mandates, payees, routing catalogue, versioned rules, payment files, manual decisions, recurring payments, sandbox simulators | Bank8:Payments |
| 3 | Open banking | FDX v6.5 provider APIs, consent lifecycle + enforcement, CSDF data minimization, recipient registration (DDCR/DDPM), HMAC-signed notifications, certification metrics | OpenFin8:CA |
| 4 | Regulatory reporting | Jurisdiction registry as runtime data; filing calendar; return generation + XBRL/CSV packaging; submission/amendment lifecycle; AML/CTF filing (STR/SAR/CTR/EFTR/LCTR) - the vertical's single filing executor | Bank8:Reporting |
| 5 | Prudential risk | Continuous exposure measurement from posting/payment events; Basel capital, LCR/NSFR liquidity, IFRS 9 ECL staging; limit monitoring with breach events; declarative stress scenarios | Bank8:Risk |
| 6 | AML/CTF compliance | KYC/CDD, beneficial ownership, PEP determination, customer risk rating; real-time sanctions screening + transaction monitoring; alert/case lifecycle - detection only, filing via Reporting | Bank8:Compliance |
| 7 | Customer banking app | Sign-up/sign-in, account opening, balances/transactions, transfers, statements, notifications, consent review/revocation | apps/ebank |
| 8 | FDX recipient app | Provider discovery, consent journeys, consented account/transaction data | apps/efintech |
| 9 | Branch teller terminal | Customer search/onboarding, CIBA-delegated counter operations (cash/cheque deposits, withdrawals, transfers), receipts, ops cockpit (batches, DLQ, decisions, tasks) | apps/eteller |
| 10 | Vertical admin console | Single staff console rendering the services' RFW admin pages; service health + per-environment service enablement | apps/admin |
| 11 | Shared contracts & SDK | Typed wire DTOs and a unified Rust SDK facade (`bank8::{service}`) for internal and third-party integrators | crates/*/contracts, sdk/rust/bank8 |
| 12 | Quality & delivery gates | UI-only Playwright E2E lifecycle; Debian packaging (.deb with binaries + SQL + registry + app assets) | bank8-e2e, packaging/debian |

**What the vertical does NOT own (business boundary):**

| Out of scope | Owned by |
|---|---|
| Identity, sign-in, consent/authorization UI, CIBA approval journeys | Sentin8:Auth |
| Client session custody, token attach, proxy, delegation gateway | Sentin8:BFF |
| Event transport/durability, consumer DLQ, relay delivery | Sentin8:Bus |
| Multi-step workflow execution, retries, wait states | Sentin8:Flow |
| Schedule timing (recurring jobs, statement runs) | Sentin8:Cron |
| Tenant-authored executable hooks (WASM) | Sentin8:Func |
| Statement/document bytes | Sentin8:Storage |
| Business metrics aggregation | Sentin8:Stat |
| Org/env/app store lifecycle, service enablement | Sentin8:Sys / Sentin8:App |
| Ingress, TLS, hostname→instance resolution | Sentin8:Proxy / Sentin8:TLS |

## 3. Business Capabilities

### 3.1 Core banking (Bank8:Ledger)

| Capability | Business rule |
|---|---|
| Customers | Every banking customer is registered with at most one platform identity linkage. |
| Accounts | A customer account must reference an active product and a customer; internal accounts belong to the bank's own `institution` customer and are invisible to bank customers. |
| Product factory | Products are data: typed parameter sets compose validation modules; parameters resolve global → product → account; launching/changing products needs no engineering. |
| Postings | A posting batch must net to zero per denomination or it is rejected before anything is written; every movement is idempotent; original postings are never mutated - corrections are adjustments. |
| Balances | Three-dimensional balances (denomination, address, phase) with end-of-day history; concurrent postings serialize on the balance row. |
| Time-driven movement | Schedules generate posting batches through the same engine; Cron owns timing, the ledger owns correctness (schedule retries are idempotent per schedule+date). |
| Statements | Statement documents are generated per account/period into Storage and regenerate idempotently on demand. |
| Trail | Every change lands in a checksum-chained, replayable journal plus a fail-closed audit trail. |
| Bulk & control | Account migrations/update batches with per-item retry; processing groups pause/resume batch windows. |
| Seeded plumbing | Internal counterparty accounts (interest, fee, penalty, teller cash/cheque/clearing/suspense) are seeded per denomination when the ledger is enabled - every booked amount has a real counterparty account. |

### 3.2 Payment orchestration (Bank8:Payments)

| Capability | Business rule |
|---|---|
| Instructions | Every instruction is idempotent and guarded by a state machine: `pending → processing → completed/failed/cancelled`, with `waiting` for manual decisions and async scheme callbacks; terminal states never regress. |
| Scheme flows | B8 on-us, SEPA, TIPS and SWIFT AGI run over a typed ISO 20022 catalogue with UETR tracking and ISO 8583 decline mapping; every money movement is posted through Bank8:Ledger's public API - payments never balance directly. |
| Cards | Card issuing, 5-state lifecycle, PIN management, velocity controls, and 3-D Secure run as first-class business objects. |
| Mandates & payees | pain.009 mandates and the payee registry bind payment initiation to approved counterparties and amount limits. |
| Rules & routing | Versioned rule-set drafts never execute until published; the routing catalogue binds instruments to routes and rules. |
| Files | Payment files are ingested, submitted, and debatched per-file with a dedicated Flow workflow per step. |
| Decisions & tasks | Manual decisions and approval tasks require an audited actor claim; availability (503) is never conflated with authorization (403). |
| Recurring | Recurring/scheduled payments register with Sentin8:Cron; timing is platform-owned, execution re-enters the same instruction pipeline. |
| Sandbox | Scheme simulators (cards, credit transfers, FedNow, SWIFT AGI) exercise production-parity paths for integration testing without live schemes. |

### 3.3 Open banking (OpenFin8:CA)

| Capability | Business rule |
|---|---|
| Consent control | No consent, no data: every provider route passes consent middleware (valid, unexpired, scope-covered) on top of RLS - a route cannot bypass it; revocation stops serving on the very next call. |
| Consent lifecycle | `ACTIVE → REVOKED` (reason + initiator recorded) or `ACTIVE → EXPIRED` via the consent's duration window (`ONE_TIME` / `PERSISTENT` / `TIME_BOUND` + lookback); expiry is introspection-driven, never cached. |
| Data minimization | Responses are projected to the granted CSDF clusters before serialization, narrowed by scope, product category, and requested fields; unknown scopes grant nothing. |
| Recipient onboarding | External recipients register dynamically (RFC 7591/7592 DCR proxy) with DPoP sender-constrained tokens; no static recipient list exists. |
| Data serving | Consented accounts, transactions, statements, and customer info are served through `/fdx/v6/*`; unimplemented FDX families (rewards, tax forms, investments) return the standard FDX unsupported response. |
| Money movement | Recipient-initiated transfers/payments are consent-checked by FDX and executed by Bank8:Payments - one executor for money movement. |
| Notifications | Delivery pushes HMAC-signed webhook notifications per subscription with retry backoff; exhausted deliveries are marked failed for admin triage, never silently dropped. |
| Certification | `/fdx/v6/certification-metrics` derives data-call and consent-transition evidence from audited traffic for FDX certification review. |

### 3.4 Experiences (apps)

| App | Persona | Capability rules |
|---|---|---|
| ebank | Retail customer | Self-service onboarding, account opening (13 product types), transfers (idempotent by construction), statements via signed URLs, consent view/revoke; no credential ever reaches the client. |
| efintech | Fintech customer (recipient) | Discovers published providers, starts consent journeys (hosted approval), consumes only consent-scoped data; revocation removes data on the next refresh. |
| eteller | Branch teller | Customer search/onboarding run on the staff token; all customer operations ride customer-approved CIBA delegation (`act` = teller), time-boxed and audited; internal accounts resolve staff-only. |
| admin | Bank staff | One console for the whole vertical: services' RFW admin pages, service health, per-environment service enablement; every mutation admin-scoped and audited upstream. |

## 4. Business Events (Outbound)

The vertical's complete event surface is three Bus families plus one inbound
platform trigger (event naming: `bank8:{service}:{resource}:{operation}`):

| Family | Producer | Volume | Business meaning |
|---|---|---|---|
| `bank8:ledger:*` | Bank8:Ledger | 30 resource types | every account/product/posting/schedule/adjustment lifecycle change - downstream recon, statement triggers, AI fraud-scan hook |
| `bank8:payments:*` | Bank8:Payments | 25 resource types (+ specific flows: retried/cancelled/repaired/wasm-migrated) | instruction lifecycle, card/cardholder lifecycle, rules publishing, files, decisions - drive the embedded re-drive worker and downstream consumers |
| `bank8:open-ca:*` | OpenFin8:CA | 16 resource types | consent granted/revoked/expired, recipient registrations, PIP parties, notification subscriptions - drive recipient-side reconciliation |

**Inbound (consumed):**

| Event | Consumer | Reaction |
|---|---|---|
| `sentin8:sys:service:updated {enabled}` | ledger + fdx env-init consumers | idempotent per-tenant seeding - internal counterparty accounts; provider profile + recipient-client registration |
| `bank8:payments:instruction:*` | payments embedded worker | guarded re-drive of stalled/failed instructions via Flow |
| `bank8:payments:instruction:completed` | ledger trigger (registered) | posting callback reconciliation |

## 5. Business Rules & Invariants

1. **Books never drift** - a posting batch that does not balance per
   denomination is rejected before any row is written.
2. **Money movement has one executor** - all movement, from app transfers to
   FDX-initiated payments, realizes as Bank8:Ledger postings via the public
   API; no service ever writes another's balances or tables.
3. **Retries are safe by construction** - posting/instruction idempotency keys
   are unique per tenant; teller retries, FDX money movement replays, and
   schedule re-runs can never double-post.
4. **Terminal states are final** - completed/cancelled/revoked/closed states
   never regress; every state transition is a guarded update.
5. **No consent, no data** - external data access exists only inside an
   explicit customer consent; revocation takes effect immediately.
6. **Minimization is structural** - only CSDF-granted clusters are ever
   serialized; scope, product category, and requested fields can only narrow.
7. **The teller never holds customer credentials** - counter operations ride
   customer-approved, time-boxed delegation, attributable to the teller.
8. **The bank's plumbing is not the customer's business** - internal accounts
   are seeded, owned by the institution customer, and visible only to staff
   surfaces.
9. **Every row is tenant-isolated** - FORCE-RLS on `env_id` across all 114
   domain tables, with holder-scoping on customer-held records.
10. **Money is exact** - `rust_decimal` end to end; the JSON wire format is a
    decimal string.
11. **Secrets are referenced, never stored** - provider tokens, recipient
    keys, and notification secrets live as secret references (including the
    sealed DPoP key reference).
12. **Drafts never execute** - unpublished rule versions cannot affect
    payment outcomes; simulators are explicit, production-parity paths.

## 6. Target-User Roles & Use Cases

| Persona | What they do with the vertical |
|---|---|
| Retail customer | Banks end-to-end from the eBank app: sign-up, open products, monitor balances/transactions, transfer, download statements, grant/revoke FDX sharing. |
| Fintech customer | Uses the eFintech app to discover the bank as a provider, consent, and view consented account/transaction data. |
| Branch teller | Serves walk-in customers from eTeller: onboarding, customer-approved counter operations, receipts. |
| Branch operations staff | Administers batches, DLQ replay, manual decisions, approval tasks from the admin console. |
| Bank administrator | Manages products, FDX provider profile, recipient registrations, service enablement, and monitors health from the admin console. |
| External FDX recipient (machine persona) | Registers dynamically, consumes consented data under CSDF minimization, receives signed notifications. |
| Platform operator | Installs the vertical once per tenant environment (enable three services); everything else is vertical-owned and automated. |
| Integrator | Builds against the unified Rust SDK facade and typed contracts. |

## 7. KPIs / Success Criteria

- **Financial correctness:** zero unbalanced batches committed; zero
  double-posted instructions across all retry paths.
- **Reliability:** all vertical journeys pass the UI-only E2E lifecycle
  (sign-up → products → teller delegation → deposit → consent → recipient
  data) without direct backend access.
- **Latency:** synchronous posting path completes within interactive budget
  (single Flow hop for orchestration; atomic ledger commit); FDX reads served
  from consent-checked single-pass middleware.
- **Security:** zero token/credential exposure incidents; every M2M
  credential certificate-bound; every cross-tenant probe denied and audited.
- **Compliance:** every domain mutation journaled (checksum-chained) and
  audited; FDX certification evidence produced from real traffic.
- **Operability:** tenant enablement is one toggle per service; upgrades are
  rolling and zero-downtime (drain-gauged).

## 8. Dependencies & Reliance on Other Services

| Dependency | Why the business relies on it |
|---|---|
| Sentin8:Auth | Identity plane, hosted sign-in/consent UI, CIBA, DCR for every workload and recipient |
| Sentin8:BFF | Token custody, scope gating, proxy, delegation gateway (teller CIBA) |
| Sentin8:Bus | Event durability, consumer groups, DLQ, SSE consume for the payments worker and env-init consumers |
| Sentin8:Flow | Payment orchestration engine (step execution, retries, wait states, file debatch, statement regeneration) |
| Sentin8:Cron | Timing for schedules and recurring payments |
| Sentin8:Func | Tenant-authored hooks (the vertical composes, Func executes) |
| Sentin8:Storage | Statement and document byte custody |
| Sentin8:Stat | Business metrics aggregation |
| Sentin8:Sys / Sentin8:App | Org/env lifecycle, service enablement events, app store listings |
| Sentin8:Proxy / Sentin8:TLS | Ingress, post-quantum TLS, hostname→instance resolution |

## 9. Acceptance Criteria

1. A tenant environment can be brought from zero to full banking by enabling
   the three services - internal accounts, provider profile, and recipient
   registration self-seed from the platform's service-updated event.
2. A customer can open a product and transfer money in the eBank app; a
   retried transfer never double-posts.
3. A teller can serve a customer with the customer's remote approval only;
   no teller path executes customer operations on staff authority.
4. An external recipient can register dynamically, obtain consent, and
   retrieve only the consented, minimized data; revocation cuts access on the
   next call.
5. Every instruction reaches a terminal state through the Flow engine with
   audited steps; stalled instructions re-drive via the embedded worker.
6. All 114 domain tables are FORCE-RLS'd; cross-tenant access is denied and
   audited.
7. The UI-only E2E lifecycle passes end to end through real user journeys.
8. The vertical installs as a Debian package (`bank8` depending on
   `sentin8` + `sentin8-common`) and enrolls declaratively (
   `vertical enroll`).
9. FDX certification evidence (contract, security, CSDF, operational tests +
   metrics) is produced and reviewable.
10. Every capability in this document is covered by its unit's
    `BUSINESS.md` and exercised by tests or the E2E suite.

## 10. Open Business Questions

- **Live scheme certification** (Visa DPS/MDES, SWIFT AGI) is tenant-driven
  by design - the vertical ships the runbook and simulators; when does a
  tenant need production scheme accreditation to go live?
- **Recurring payments** operate behind the `v1beta` surface until the
  recurring E2E spec is exercised - what is the promotion bar?
- **eTeller page set 2** (card management, payment instructions, file
  upload, simulator, mandates, standing orders, closure/freeze) extends the
  counter surface - where does counter scope end and admin-console scope
  begin? (BACKLOG ETA-5)
- **FDX certification daily-rollup table + evidence admin page** are deferred
  until poll-volume scale demands them - what review volume triggers the
  build? (fdx DESIGN.md §10)

---

**Architecture & Design:** bank8 and its underlying concepts were designed by [Hamid Jahanzad](https://www.linkedin.com/in/hamidjahanzad/).
