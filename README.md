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

// Smart proof selection with fee consideration
if let (selectedProofs, changeProofs, totalFee) = CashuSwift.pick(
    proofs,
    amount: 42,
    mint: mint,
    ignoreFees: false
) {
    print("Selected proofs worth \(selectedProofs.sum) sats")
    print("Total fee: \(totalFee) sats")
}
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

1. **Always verify DLEQ proofs** when minting or melting to ensure the mint is not cheating
2. **Use deterministic secrets** (with a seed) for backup and recovery capability
3. **Store derivation counters** returned from operations to maintain proper state
4. **Handle fees appropriately** by checking `inputFeePPK` on keysets
5. **Check proof states** before attempting to spend them
6. **Use P2PK locking** for secure peer-to-peer transfers

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

// Select proofs for exact amount
if let (selected, remaining) = proofs.pick(42) {
    print("Selected proofs: \(selected.sum) sats")
    print("Remaining proofs: \(remaining.sum) sats")
}

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
