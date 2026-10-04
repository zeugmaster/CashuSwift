# CashuSwift library for Cashu Ecash

This library provides basic functionality and model representation for using the Cashu protocol via its V1 API.

:warning: This package is not production ready and its APIs will change. Please use it only for experimenting and with a test mint offering `FakeWallet` ecash.

## Implemented [NUTs](https://github.com/cashubtc/nuts/):

### Mandatory

| #    | Description                       |
|----------|-----------------------------------|
| [00][00] | Cryptography and Models           |
| [01][01] | Mint public keys                  |
| [02][02] | Keysets and fees                  |
| [03][03] | Swapping tokens                   |
| [04][04] | Minting tokens                    |
| [05][05] | Melting tokens                    |
| [06][06] | Mint info                         |

### Optional

| # | Description | Status
| --- | --- | --- |
| [07][07] | Token state check | :heavy_check_mark: |
| [08][08] | Overpaid Lightning fees | :heavy_check_mark: |
| [09][09] | Signature restore | :heavy_check_mark: |
| [10][10] | Spending conditions | :heavy_check_mark: |
| [11][11] | Pay-To-Pubkey (P2PK) | :heavy_check_mark: |
| [12][12] | DLEQ proofs | :heavy_check_mark: |
| [13][13] | Deterministic secrets | :heavy_check_mark: |
| [14][14] | Hashed Timelock Contracts (HTLCs) | :construction: |
| [15][15] | Partial multi-path payments (MPP) | N/A |
| [16][16] | Animated QR codes | N/A |
| [17][17] | WebSocket subscriptions  | :construction: |
| [30][30] | Onchain deposits and withdrawals | :heavy_check_mark: |


## Basic Usage

All operations use the `CashuSwift` namespace and support both protocol-based generic types and concrete implementations.
Protocol based generics will soon be retired because concrete types allow for `Sendable` conformance.

### Initializing a Mint

```swift
import CashuSwift

// Initialize a mint with its URL
let mintURL = URL(string: "https://testmint.macadamia.cash")!
let mint = try await CashuSwift.loadMint(url: mintURL)

// Check if mint is reachable
let isOnline = await mint.isReachable()

// Get mint info
let info = try await CashuSwift.loadInfoFromMint(mint)
```

### Minting Ecash (Lightning → Ecash)

```swift
// Get a mint quote for 100 sats
let amount = 100
let mintQuoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: amount)
let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: mintQuoteRequest)

// After paying the Lightning invoice, mint the ecash
// Using deterministic secrets with a seed for backup capability
let seed = "your-secret-seed-phrase"
let (proofs, validDLEQ) = try await CashuSwift.issue(
    for: quote,
    with: mint,
    seed: seed,
    preferredDistribution: nil  // Uses optimal base-2 distribution by default
)

print("Minted \(proofs.count) proofs totaling \(proofs.sum) sats")
print("DLEQ verification: \(validDLEQ ? "✓ Passed" : "✗ Failed")")
```

### BOLT12 minting and quote signing

BOLT12 mint quotes require NUT-20 authorization. Keep the quote's private key
(or its seed derivation counter) so every issuance against that quote can be
signed, including after restarting the wallet.

```swift
// seedHex is the wallet's hex-encoded seed. Reserve and persist a fresh
// quoteCounter for this quote, independently of NUT-13 output counters.
let quoteKey = try CashuSwift.Bolt12.quoteLockingKey(
    seed: seedHex, counter: quoteCounter
)
let quote = try await CashuSwift.Bolt12.requestMintQuote(
    .init(unit: "sat", amount: nil, pubkey: quoteKey.publicKey),
    from: mint
)
// Persist the quote and its key/counter before presenting quote.request for payment.

// After payment, refresh the quote to read its cumulative accounting.
let updated = try await CashuSwift.Bolt12.mintQuoteState(quote.quote, from: mint)
let available = try updated.mintableAmount
if available > 0 {
    let result = try await CashuSwift.Bolt12.mint(
        quote: updated,
        from: mint,
        amount: available, // A smaller positive amount is also allowed.
        seed: seedHex,
        quoteKey: quoteKey.privateKey
    )
    // Inspect result.dleqResult before crediting proofs. Persist the returned
    // proofs and the consumed output counters; CashuSwift does not store them.
}
```

Serialize issuance attempts for each quote and refresh it between partial
issuances. The quote signing key stays the same for that quote; the wallet must
reserve and advance NUT-13 output counters for each issuance. `seed` controls
output derivation and does not replace `quoteKey`.

Migration from 0.4.3:

- Pass `quoteKey:` to typed `Bolt12.mint`. The unsigned overload is deprecated
  and throws `CashuError.quoteSigningKeyRequired` without contacting the mint.
- Read the balance with `try quote.mintableAmount`. Negative or inconsistent
  paid/issued totals throw `CashuError.invalidQuoteAccounting`.
- Typed BOLT12 uses the current NUT-20 signature format. The generic signed API
  retains its existing defaults and explicit `.legacyConcat` compatibility option.

### Onchain deposits and withdrawals (NUT-30)

`CashuSwift.Onchain` supports Bitcoin payments through a mint. The mint creates
deposit addresses and broadcasts withdrawals. Your application persists wallet
state and controls polling; this package does not run a Bitcoin wallet or node.

Check the enabled method and its limits before presenting a payment:

```swift
let info = try await CashuSwift.loadInfoFromMint(mint)
let depositSettings = try CashuSwift.Onchain.settings(
    in: info, unit: "sat", direction: .mint
)
let withdrawalSettings = try CashuSwift.Onchain.settings(
    in: info, unit: "sat", direction: .melt
)
// settings throws if the method is missing or disabled for this unit/direction.
// Display minAmount, maxAmount, and depositSettings.confirmations when present.
```

#### Deposit Bitcoin and issue ecash

```swift
let key = try CashuSwift.Onchain.quoteLockingKey(seed: seedHex, counter: quoteCounter)
let quote = try await CashuSwift.Onchain.requestMintQuote(
    .init(unit: "sat", pubkey: key.publicKey), from: mint, info: info
)
// Persist the quote, mint URL, and key reference/counter before showing quote.request.
// Advance quoteCounter independently of the NUT-13 output counters.
// Pay the Bitcoin address in quote.request using an external Bitcoin wallet.

let updated = try await CashuSwift.Onchain.mintQuoteState(quote, from: mint)
let amount = updated.mintableAmount
if amount > 0 {
    let prepared = try CashuSwift.Onchain.prepareMint(
        quote: updated, from: mint, amount: amount, seed: seedHex,
        quoteKey: key.privateKey, info: info
    )
    // Securely persist JSONEncoder().encode(prepared) before submitting.
    // Reserve material.counterRange and persist its next value in your keyset counters.
    let result = try await CashuSwift.Onchain.mint(context: prepared, from: mint)
    switch result.recovery {
    case .complete(let proofs):
        // Atomically store verified proofs and finalize the operation record.
        // Refresh the quote before another issuance, using your updated counters.
        _ = proofs
    case .failed(let reason):
        // Retain prepared and result.promises for recovery; do not credit value.
        _ = reason
    case .pending:
        break
    }
}
```

`mintableAmount` includes eligible confirmed deposits minus previously issued
ecash. You may issue a smaller positive amount within the mint's limits. Each
deposit UTXO must meet the advertised minimum; several small UTXOs do not combine
to reach it. Do not send new payments after quote expiry. A transaction detected
before expiry can confirm afterward, so keep monitoring the original quote.
The refresh overload taking a previous quote checks its identity and ignores
older accounting snapshots.

If the mint response is lost, reload the saved `MintContext` and call
`Onchain.restoreMint(context:from:)`. It retrieves signatures for those exact
outputs, including when you used random secrets (`seed: nil`). A pending recovery
does not authorize a new issuance. Serialize attempts for each quote.

#### Withdraw ecash to a Bitcoin address

```swift
let quote = try await CashuSwift.Onchain.requestMeltQuote(
    .init(unit: "sat", request: bitcoinAddress, amount: 5_000),
    from: mint, info: info
)
// Present quote.feeOptions and explicitly choose a feeIndex.
// feeIndex is an identifier, not an array position or a block estimate.
let selectedQuote = try quote.selectingFee(index: chosenFeeIndex)
let selection = try CashuSwift.selectProofs(
    availableProofs,
    targetAmount: selectedQuote.requiredInputAmount(inputFee: 0),
    mint: mint, unit: "sat", purpose: .melt
)
let prepared = try CashuSwift.Onchain.prepareMelt(
    quote: quote, feeIndex: chosenFeeIndex, from: mint,
    proofs: selection.selected, seed: seedHex, info: info
)
// In one durable application transaction:
// - reserve prepared.inputs so another operation cannot select them;
// - save JSONEncoder().encode(prepared), which contains sensitive recovery data;
// - advance prepared.material.counterRange, if present.
let submitted = try await CashuSwift.Onchain.melt(context: prepared, from: mint)
// submitted.quote.state is .pending. This call does not wait for Bitcoin blocks.

// A bounded polling example. Persist the operation when the polling window ends.
for attempt in 0..<30 {
    try Task.checkCancellation()
    let result = try await CashuSwift.Onchain.meltState(context: prepared, from: mint)
    if result.quote.state == .paid {
        switch result.changeRecovery {
        case .complete(let change):
            // Atomically upsert change by proof identity, mark inputs spent,
            // and complete the operation. Repeated polls return the same proofs.
            _ = change
        case .failed(let reason):
            // Payment settled, but change needs recovery. Retain context and quote.
            // Keep inputs unavailable and record the change-recovery failure.
            _ = reason
        case .pending:
            break
        }
        break
    }
    let seconds = min(2 + attempt * 2, 30)
    try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
}
```

Use bare Bitcoin addresses; BIP21 parsing belongs to the application and the mint
validates the destination network/checksum. Prepare unlocked proofs first.
`outpoint` identifies the broadcast payment when supplied by the mint; CDK 0.18
reports it at settlement. Settlement always requires `.paid`.
Input fees are counted once, in addition to the chosen onchain reserve. Returned
change may include unused reserve and denomination overpayment.

On timeout, cancellation, or a malformed response, keep the context and inputs
reserved. Resume with `meltState(context:from:)`, including after quote expiry.
Reconcile the quote and proof states before considering another submission.
The library performs no automatic withdrawal retries. Transport errors retain
their original type; `Onchain.Error.http(status:mintCode:)` reports structured
HTTP failures without echoing server text or proof secrets.

Both context types have a format version and include output secrets, blinding
factors, and the original keyset. Store them securely. Only
`RecoveryResult.complete` contains verified proofs; missing/invalid DLEQ and
malformed promises are explicit recovery failures. Existing Lightning result
types retain their advisory DLEQ behavior.

Run the independent [onchain regtest suite](Tests/OnchainRegtest/README.md) for a
complete executable example using pinned CDK and Bitcoin Core versions.

### Sending Ecash

```swift
// Simple send - all proofs go into the token
let (token, change, outputDLEQ) = try await CashuSwift.send(
    inputs: proofs,
    mint: mint,
    amount: nil,  // Send all
    seed: seed,
    memo: "Thanks for the coffee!"
)

// Serialize token for sharing
let tokenString = try token.serialize(.V3)  // or .V4 for CBOR format
print("Send this token: \(tokenString)")

// Partial send with change
let (partialToken, changeProofs, _) = try await CashuSwift.send(
    inputs: proofs,
    mint: mint,
    amount: 21,  // Send only 21 sats
    seed: seed,
    memo: nil
)

// Send with P2PK (Pay-to-Public-Key) locking
let recipientPublicKey = "02a1b2c3..."  // 33-byte compressed public key
let (lockedToken, change, _) = try await CashuSwift.send(
    inputs: proofs,
    mint: mint,
    amount: 50,
    seed: seed,
    memo: "Locked to your key",
    lockToPublicKey: recipientPublicKey
)
```

### Receiving Ecash

```swift
// Receive a token
let tokenString = "cashuAey..."
let token = try tokenString.deserializeToken()

// Simple receive (for unlocked tokens)
let (receivedProofs, inputDLEQ, outputDLEQ) = try await CashuSwift.receive(
    token: token,
    of: mint,
    seed: seed,
    privateKey: nil
)

// Receive P2PK-locked token
let privateKeyHex = "your-32-byte-private-key-hex"
let (unlockedProofs, _, _) = try await CashuSwift.receive(
    token: lockedToken,
    of: mint,
    seed: seed,
    privateKey: privateKeyHex
)
```

### Melting Ecash (Ecash → Lightning)

```swift
// Get a melt quote for a Lightning invoice
let invoice = "lnbc100n1..."
let meltQuoteRequest = CashuSwift.Bolt11.RequestMeltQuote(
    unit: "sat",
    request: invoice,
    options: nil
)
let meltQuote = try await CashuSwift.getQuote(mint: mint, quoteRequest: meltQuoteRequest)

// Generate blank outputs for potential fee return (NUT-08)
let blankOutputs = try CashuSwift.generateBlankOutputs(
    quote: meltQuote as! CashuSwift.Bolt11.MeltQuote,
    proofs: proofs,
    mint: mint,
    unit: "sat",
    seed: seed
)

// Melt proofs to pay the Lightning invoice
let (paid, change, dleqValid) = try await CashuSwift.melt(
    with: meltQuote,
    mint: mint,
    proofs: proofs,
    timeout: 60.0,
    blankOutputs: blankOutputs
)

if paid {
    print("Payment successful!")
    if let change = change {
        print("Received \(change.sum) sats back as change")
    }
}
```

### Checking Proof States

```swift
// Check if proofs are spent or unspent
let states = try await CashuSwift.check(proofs, mint: mint)

for (proof, state) in zip(proofs, states) {
    switch state {
    case .unspent:
        print("Proof \(proof.amount) sats: ✓ Unspent")
    case .spent:
        print("Proof \(proof.amount) sats: ✗ Spent")
    case .pending:
        print("Proof \(proof.amount) sats: ⏳ Pending")
    }
}
```

### Restoring from Seed

```swift
// Restore ecash from a seed phrase (deterministic secret recovery)
let (restoreResults, validDLEQ) = try await CashuSwift.restore(
    from: mint,
    with: seed,
    batchSize: 100  // Check 100 secrets at a time
)

for result in restoreResults {
    print("Keyset \(result.keysetID): Found \(result.proofs.count) proofs")
    print("Next derivation counter: \(result.derivationCounter)")
}
```

### Advanced Features

#### Working with Fees

```swift
// Calculate fees before operations
let inputFee = try CashuSwift.calculateFee(for: proofs, of: mint)
print("This operation will cost \(inputFee) sats in fees")
```

#### Token Formats

```swift
// Serialize to different formats
let tokenV3 = try token.serialize(.V3)  // Base64 JSON format
let tokenV4 = try token.serialize(.V4)  // CBOR binary format

// Deserialize from any format
let deserializedToken = try tokenString.deserializeToken()  // Auto-detects format

// Check token contents
for (mintURL, proofs) in deserializedToken.proofsByMint {
    print("Mint: \(mintURL)")
    print("Proofs: \(proofs.count) totaling \(proofs.sum) \(deserializedToken.unit)")
}
```

#### Error Handling

```swift
do {
    let proofs = try await CashuSwift.issue(for: quote, with: mint, seed: seed)
} catch CashuError.quotePending {
    print("Quote not paid yet")
} catch CashuError.insufficientInputs(let message) {
    print("Not enough funds: \(message)")
} catch CashuError.unitError(let message) {
    print("Unit mismatch: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Best Practices

1. **Always verify DLEQ proofs** when minting or melting to ensure the mint is not trying to fingerprint the user or when saving a locked token for later
2. **Use deterministic secrets** (with a seed) for backup and recovery capability
3. **Store derivation counters** returned from operations to maintain proper state
4. **Handle fees appropriately** by checking `inputFeePPK` on keysets
5. **Use P2PK locking** for partial offline payments or similar spending scenarios

### Additional Advanced Examples

#### Managing Multiple Mints

```swift
// Load multiple mints
let mint1 = try await CashuSwift.loadMint(url: URL(string: "https://mint1.example.com")!)
let mint2 = try await CashuSwift.loadMint(url: URL(string: "https://mint2.example.com")!)

// Keep mints updated
var mutableMint = mint
try await CashuSwift.update(&mutableMint)

// Or get updated keysets without mutating
let updatedKeysets = try await CashuSwift.updatedKeysetsForMint(mint)
```

#### Proof Management and Utilities

```swift
// Split amounts into optimal denominations
let denominations = CashuSwift.splitIntoBase2Numbers(127)  // [1, 2, 4, 8, 16, 32, 64]

// Sum proofs easily
let totalValue = proofs.sum

// Filter proofs by state
let spentStates = try await CashuSwift.check(proofs, mint: mint)
let unspentProofs = proofs.enumerated().compactMap { index, proof in
    spentStates[index] == .unspent ? proof : nil
}
```

#### Quote Management

```swift
// Check mint quote status
let mintQuoteStatus = try await CashuSwift.mintQuoteState(
    for: quote.quote,
    mint: mint
)

switch mintQuoteStatus.state {
case .paid:
    print("Quote is paid, ready to mint!")
case .unpaid:
    print("Waiting for payment...")
case .pending:
    print("Payment is being processed...")
}

// Check melt quote status
let (isPaid, change, validDLEQ) = try await CashuSwift.meltState(
    for: meltQuote.quote,
    mint: mint,
    blankOutputs: blankOutputs
)
```

#### Working with Spending Conditions

```swift
// Check if all inputs in a token are locked to a specific key
let lockStatus = try token.checkAllInputsLocked(to: recipientPublicKey)

switch lockStatus {
case .match:
    print("All proofs locked to the provided key")
case .mismatch:
    print("Proofs locked to a different key")
case .partial:
    print("Mixed: some locked, some not")
case .notLocked:
    print("No spending conditions")
case .noKey:
    print("Locked but no key provided")
}

// Sign P2PK locked proofs
let privateKey = "your-private-key-hex"
try CashuSwift.sign(all: lockedProofs, using: privateKey)
```

#### Custom Types

```swift
// You can implement your own types conforming to the protocols
struct MyCustomMint: MintRepresenting {
    var url: URL
    var keysets: [CashuSwift.Keyset]
    // Add your custom properties and methods
}

struct MyCustomProof: ProofRepresenting {
    var keysetID: String
    var amount: Int
    var secret: String
    var C: String
    // Add your custom properties and methods
}
```

## Type System

The library uses protocol-based design with concrete implementations:

- `MintRepresenting` protocol with `Mint` concrete type
- `ProofRepresenting` protocol with `Proof` concrete type
- `Quote` protocol with `Bolt11.MintQuote` and `Bolt11.MeltQuote` implementations

This allows for flexibility while maintaining type safety.


[00]: https://github.com/cashubtc/nuts/blob/main/00.md
[01]: https://github.com/cashubtc/nuts/blob/main/01.md
[02]: https://github.com/cashubtc/nuts/blob/main/02.md
[03]: https://github.com/cashubtc/nuts/blob/main/03.md
[04]: https://github.com/cashubtc/nuts/blob/main/04.md
[05]: https://github.com/cashubtc/nuts/blob/main/05.md
[06]: https://github.com/cashubtc/nuts/blob/main/06.md
[07]: https://github.com/cashubtc/nuts/blob/main/07.md
[08]: https://github.com/cashubtc/nuts/blob/main/08.md
[09]: https://github.com/cashubtc/nuts/blob/main/09.md
[10]: https://github.com/cashubtc/nuts/blob/main/10.md
[11]: https://github.com/cashubtc/nuts/blob/main/11.md
[12]: https://github.com/cashubtc/nuts/blob/main/12.md
[13]: https://github.com/cashubtc/nuts/blob/main/13.md
[14]: https://github.com/cashubtc/nuts/blob/main/14.md
[15]: https://github.com/cashubtc/nuts/blob/main/15.md
[16]: https://github.com/cashubtc/nuts/blob/main/16.md
[17]: https://github.com/cashubtc/nuts/blob/main/17.md
[30]: https://github.com/cashubtc/nuts/blob/main/30.md
