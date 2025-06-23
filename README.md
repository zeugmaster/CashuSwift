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

Most methods on `Mint` have additional parameters for customizing their behaviour (e.g. `preferredDistribution`, `seed` for deterministic secret generation).
The library defines basic types like `Mint`, `Proof` etc., that conform to corresponding protocols. This allows a library user to either reuse these types or define their own in accordance with these protocols.


#### Initializing a mint

```swift
let mintURL = URL(string: "https://testmint.macadamia.cash")!
let mint = try await Mint(with: mintURL)
```

#### Minting ecash 

```swift
let amount = 511
let quote = try await CashuSwift.getQuote(mint: mint,
                                          quoteRequest: CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                                                           amount: amount))
let proofs = try await CashuSwift.issue(for: quote, on: mint) as! [CashuSwift.Proof]
```

#### Sending ecash

```swift
let (token, change) = try await CashuSwift.send(mint: mint, proofs: proofs, amount: 15)

// The token object can be serialized to a string (currently only V3 format supported)
let tokenString = try token.serialize(.V3)
```

#### Receiving ecash

```swift
let token = try "cashuAey...".deserializeToken()
// This will swap the ecash contained in the token and return your new proofs
let proofs = try await CashuSwift.receive(mint: mint, token: token)
```

#### Melting ecash

```swift
let quoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat", request: q2.request, options: nil)
let quote = try await CashuSwift.getQuote(mint:mint, quoteRequest: quoteRequest)

let result = try await CashuSwift.melt(mint: mint, quote: quote, proofs: proofs)
// result.paid == true if the Bolt11 lightning payment successful
```        


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
