# Onchain support implementation plan

- Branch: `feat/onchain`
- Baseline: `a4383d8` (`Fix NUT-20 signing for typed BOLT12 minting`)
- Prepared: 2026-09-15
- Status: implemented; offline tests and CDK/Bitcoin regtest acceptance pass.

## Implementation record

- Added `Onchain.swift`, `OnchainContext.swift`, and `OnchainOperations.swift` with typed quotes, availability settings, prepared mint/melt contexts, strict promise verification, and recovery APIs.
- Signing reuses the existing NUT-20 crypto and signed execution body. Onchain prepares and persists outputs before submission rather than using `_mintSigned`, which generates outputs inside the network operation.
- Onchain uses an internal strict transport path and its own recovery result, preserving existing Lightning API behavior. Returned proofs are available only after passing DLEQ. Paid withdrawals retain a separate change-recovery result.
- Added `restoreMint(context:from:)` for lost issuance responses, including random-secret outputs. Stored keyset snapshots support withdrawal change recovery after rotation.
- Pinned NUT-30 revision `f364a04162febbb8e860a3f121cd32d3d472cb44`; integration uses immutable CDK 0.18.0 and Bitcoin Core 29.0 images. See `Tests/OnchainRegtest/README.md` for observed CDK compatibility details.
- Local verification: 157 offline tests passed, the enabled regtest acceptance test passed, and the iOS device build succeeded. The installed compiler is Swift 6.3.3 in Swift 5 language mode with the existing Swift-tools 5.9 manifest and StrictConcurrency setting. A separate Swift 5.9 compiler is unavailable.
- watchOS/tvOS builds were attempted; Xcode reports their platform components are not installed. The regtest runner is ready for a dedicated macOS/Docker CI job; this repository has no existing CI workflow to extend.

## Goal and scope

Add `CashuSwift.Onchain` so a wallet can deposit Bitcoin into a supporting Cashu mint and withdraw ecash to a Bitcoin address. Support capability discovery, typed quotes, signed issuance, explicit fee selection, payment tracking, and recoverable change handling.

Keep the library stateless: the application stores keys, proofs, counters, and operation records. Preserve existing BOLT11, BOLT12, and Generic public APIs. Bitcoin transaction construction, node operation, coin selection for Bitcoin UTXOs, fee bumping, and wallet UI remain outside this package. Start interoperability testing with `sat`; require an advertised matching unit for every operation and avoid implicit unit conversions.

## Protocol baseline

Implement [NUT-30](https://github.com/cashubtc/nuts/blob/main/30.md), checked on the preparation date:

- Deposits use a Bitcoin address and require quote locking. Accounting reflects eligible confirmed deposits; one quote can support repeated payments and partial issuance.
- The deposit minimum applies to each UTXO. Expiry concerns when the mint first detects a payment; already detected transactions can confirm later.
- Withdrawal quotes offer indexed fee choices. Execution chooses `fee_index`; `selected_fee_index` reports the mint's selection. These are identifiers, not array positions or confirmation estimates.
- Withdrawal execution returns `PENDING`. Poll until settlement; `outpoint` identifies the transaction output after broadcast. Broadcasting alone is not confirmation.

Use [NUT-04](https://github.com/cashubtc/nuts/blob/main/04.md) for quote accounting and stale-response handling, [NUT-05](https://github.com/cashubtc/nuts/blob/main/05.md) for melt lifecycle, [NUT-20](https://github.com/cashubtc/nuts/blob/main/20.md) for signing, and [NUT-08](https://github.com/cashubtc/nuts/blob/main/08.md) for change.

Before implementation, pin the NUTs commit and a compatible test-mint revision in the fixtures. Current NUT-30 examples contain inconsistencies: one fee-options example omits indexes, and a blank-output example uses amount `1`. Follow the normative indexed schema and NUT-08's zero-valued blanks; do not add inferred compatibility behavior without a documented fixture.

## Existing code to reuse

| Area | Current support | Required work |
| --- | --- | --- |
| `Models/PaymentMethods/PaymentMethodID.swift` | Extensible method identifiers | Add `.onchain`. |
| `Models/PaymentMethods/QuoteProtocols.swift` | Optional mint state and throwing melt funding calculation | Add conformances; correct outdated onchain field comments. |
| `Models/PaymentMethods/Bolt12.swift` | Validated cumulative balances, quote keys, signed partial issuance | Reuse this structure; add timestamp-aware refresh for onchain. |
| `Operations/PaymentBackendOperations.swift` | Generic quote endpoints, `_mintSigned`, execution body builders | Reuse routing/signing; add strict response handling needed below. |
| `Models/MintInfo.swift` | Method/unit lookup and opaque method options | Add typed onchain settings and an availability check respecting `disabled`. |
| `Operations/ProofSelection.swift`, `Operations/misc.swift` | Fee-aware selection and blank generation | Feed the chosen reserve into selection; validate arithmetic and recovery metadata. |
| `Models/Results.swift` | Typed `MeltResult`, in-memory proofs and DLEQ results | Add an onchain operation context and explicit change-recovery status. |
| `Tests/cashu-swiftTests/Bolt12MintTests.swift` | Local HTTP stubs and signature assertions | Extract reusable test support and extend it to pending workflows. |

The source at this baseline already validates BOLT12 accounting and signing. Some local AGENTS.md descriptions predate those fixes; use the current implementation when deciding what to reuse.

## Implementation sequence

### 1. Typed models and capability discovery

- [x] Add `Models/PaymentMethods/Onchain.swift` with `Codable`/`Sendable` mint and melt requests/quotes, fee options, and the method-specific melt execution body.
- [x] Map the normative wire fields explicitly. Include `updatedAt` in mint quotes. Expose `amount` and `state` as `nil` where the shared mint protocol needs them, without synthesizing a one-time issuance state.
- [x] Validate required fields, method identity, nonnegative accounting, supported numeric ranges, unique fee identifiers, and selection references. Reject malformed input with typed `Onchain.Error` errors; never coerce monetary values through floating point.
- [x] Add `MeltQuote.selectingFee(index:) throws -> MeltQuote`. Keep the wallet's choice separate from the server's `selectedFeeIndex` and exclude that local choice from wire coding. `requiredInputAmount(inputFee:)` must throw when no applicable choice exists.
- [x] Add a typed settings accessor over `Mint.Info.PaymentMethod.options`. Preserve unknown options. Distinguish advertised support from enabled availability, and expose limits and confirmation settings without changing existing lookup behavior.

**Complete when:** codec and validation tests cover the pinned schema, extra unknown fields, missing/null optional values, malformed numbers, and fee identifiers that are unordered and non-contiguous.

### 2. Deposits and signed issuance

- [x] Expose `Onchain.quoteLockingKey`, `requestMintQuote`, `mintQuoteState`, and `mint`, following BOLT12 naming and using the existing crypto implementation.
- [x] Bind initial responses to the requested key and unit. Provide refresh against a previous quote so ID, address, key, unit, and accounting timestamp can be checked together.
- [x] Provide a pure merge/validation helper for refreshed accounting. Ignore older timestamps; reject inconsistent equal-timestamp snapshots and unexplained decreasing totals. Applications serialize updates for each quote.
- [x] Validate the requested issuance amount against the checked available balance and advertised operation limits. Reuse the NUT-20 signing primitive and signed execution body with the current signature format and equivalent distribution checks; preparation exposes recovery material before POST.
- [x] Document two independently persisted counters: quote-key derivation and output-secret derivation. Reserve output indices before POST; retain the intended distribution and keyset so an interrupted issuance can be recovered. For random secrets, expose preparation or a persistence callback for the complete output material before POST; a record created only after success is insufficient.
- [x] Make examples persist the quote and signing-key reference before presenting the address. Refresh before subsequent issuances and preserve recovery records across expiry.

**Complete when:** local HTTP tests verify signatures over the exact submitted outputs, successive partial issuances, response binding, stale refreshes, and invalid requests failing before output generation or network access.

### 3. Withdrawal preparation and fee selection

- [x] Expose `requestMeltQuote` and require an explicit choice before execution. Preserve the quoted recipient, amount, unit, and fee schedule in the operation record and validate subsequent responses against them.
- [x] Add an onchain preparation API that checks expiry, amount, funding, and fee selection before creating the execution body. Accept bare Bitcoin addresses initially; leave BIP21 parsing to the application and mint-side address validation to the backend. Do not infer a Bitcoin network from the mint URL.
- [x] Compute the proof-selection target as `amount + chosen reserve`, using checked addition; let the existing selector account for input fees once. Check totals again against the selected proofs before POST.
- [x] Reuse blank generation for the maximum potential return, including denomination overpayment. Validate tuple lengths, keyset identity, unit, and arithmetic before invoking shared helpers. Keep the existing blank-count formula.
- [x] Return a versioned, serializable `Onchain.MeltContext` before submission: mint URL, original quote, wallet fee choice, selected inputs or stable references, blank outputs with secrets/blinding factors, and consumed counter range. The application securely persists it and reserves inputs before sending.

**Complete when:** preparation round-trips through storage and produces the same request and recovery material after restart. Tests cover input fees, exact funding, excess funding, zero reserve, insufficient funds, and overflow.

### 4. Asynchronous execution and recovery

- [x] Add `Onchain.melt(context:from:)` and `meltState(context:from:)`. The execution body sends the chosen fee identifier. Return promptly after the request completes; use a normal HTTP timeout rather than waiting for blocks. A bounded polling example uses task cancellation and backoff.
- [x] Keep inputs reserved on pending, cancellation, timeout, or an ambiguous response. Poll the same quote and reconcile proof states before considering a retry or releasing inputs; never automatically submit another withdrawal. Use the existing proof-state endpoint described in [NUT-07](https://github.com/cashubtc/nuts/blob/main/07.md).
- [x] Validate quote identity, destination, amount, unit, fee schedule, and selected fee on every response. Treat changes as reconciliation failures while retaining the original context.
- [x] Recover change against the persisted blank-output keyset, including after keyset rotation. Retain inactive keysets needed for recovery. Repeated polling must produce stable proofs that callers can upsert without crediting twice.
- [x] Separate payment status from change recovery. A settled payment with invalid/unblindable change returns the quote plus a typed recovery failure and retained promises/context; it must not look like a completed payment with no change.

**Complete when:** stub tests exercise a dropped POST response, several pending polls, broadcast followed by confirmation, cancellation/restart, keyset rotation, repeated settlement responses, and failed change recovery without a second POST.

### 5. Shared safeguards required by these flows

These are prerequisites for completing steps 2–4; keep changes focused on code reached by the new APIs.

- [x] Add HTTP-status-aware decoding and structured mint-error parsing in `Network/Network.swift`; preserve transport/cancellation information. A transport error cannot prove that a POST was rejected. Preserve existing public error behavior where possible through an internal strict transport path.
- [x] Extract response-validation and change-processing helpers so onchain can validate before trusting promises. Check counts, amounts, keyset IDs, and output correspondence; require passing DLEQ before crediting returned value, per repository instructions. Surface `.fail` and `.noData` as untrusted results with recovery information.
- [x] Avoid `_melt`'s existing witness stripping in the onchain path. Preserve supplied witnesses or reject unsupported locked inputs before submission.
- [x] Check untrusted quote IDs as single URL path components and use the fixed `.onchain` route. Validate all sums/subtractions before reaching existing unchecked helpers.
- [x] Keep existing Lightning APIs source compatible and add regression coverage for any shared behavioral change. General token-parser fixes, unrelated payment-request changes, and a full networking redesign are separate work.

**Complete when:** malformed responses cannot crash the process or silently discard returned value, and focused BOLT11/BOLT12/Generic regression tests pass.

### 6. Interoperability, documentation, and release

- [x] Add `OnchainModelTests`, `OnchainMintTests`, `OnchainMeltTests`, and focused network tests under `Tests/cashu-swiftTests/`. Make offline HTTP tests deterministic and isolated from globally registered stubs.
- [x] Add an opt-in regtest integration suite using a pinned NUT-30-capable mint and Bitcoin Core. Test deposit detection, confirmation thresholds, minimum UTXO handling, repeated deposits/issuance, withdrawal fee choices, and final change recovery.
- [x] Make the opt-in integration runner fail if its required services are unavailable; report local skips as missing coverage. Never use mainnet or rely on the existing Lightning faucet to demonstrate onchain support.
- [x] Update README with complete deposit and withdrawal examples, capability checks, persistent context/counter handling, and result inspection. Add NUT-30 to the support table only after the integration acceptance criteria pass.
- [x] Run offline regressions and the dedicated integration suite with the Swift-tools 5.9 manifest and StrictConcurrency settings; verify the iOS build.
- [ ] Verify a native Swift 5.9 toolchain and watchOS/tvOS platform builds when those toolchains/platform components are available.

## Delivery order and acceptance

Suggested commits: models/settings → strict response helpers → deposit flow → withdrawal preparation/context → execution/recovery → integration/docs. Add tests with each change.

The feature is complete when an application can discover support, receive a confirmed deposit, mint valid proofs, select a withdrawal fee, persist and resume a pending withdrawal after restart, and recover its change exactly once. Existing Lightning call sites must still compile and pass their regressions.

The implementation and executable tests now live on this branch. Applications still own secure context storage, proof reservations, counter persistence, and polling. The remaining environment checks are a native Swift 5.9 toolchain build and watchOS/tvOS builds with their platform components installed.
