# CashuSwift library for Cashu Ecash

This library provides basic functionality and model representation for using the Cashu protocol.

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
| [08][08] | Overpaid Lightning fees | :construction: |
| [09][09] | Signature restore | :heavy_check_mark: |
| [10][10] | Spending conditions | :construction: |
| [11][11] | Pay-To-Pubkey (P2PK) | :construction: |
| [12][12] | DLEQ proofs | :construction: |
| [13][13] | Deterministic secrets | :heavy_check_mark: |
| [14][14] | Hashed Timelock Contracts (HTLCs) | :construction: |
| [15][15] | Partial multi-path payments (MPP) | :construction: |
| [16][16] | Animated QR codes | N/A |
| [17][17] | WebSocket subscriptions  | :construction: |

## Bindings

Experimental bindings can be found in the [bindings](./bindings/) folder.

## License

Code is under the [MIT License](LICENSE)

## Contribution

All contributions welcome.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, shall be licensed as above, without any additional terms or conditions.


## Basic Usage

#### Initializing a mint

```swift
let mintURL = URL(string: "https://testmint.macadamia.cash")!
let mint = try await Mint(with: mintURL)
```

#### Minting ecash 

```swift
let quote = try await mint.getQuote(quoteRequest: Bolt11.RequestMintQuote(unit: "sat",
                                                                          amount: 21))
let proofs = try await mint.issue(for: quote)
```

#### Sending ecash

```swift
let (token, change) = try await mint.send(proofs: proofs, amount: 15)

// The token object can be serialized to a string (currently only V3 format supported)
let tokenString = try token.serialize(.V3)
```

#### Receiving ecash

```swift
let token = try "cashuAey...".deserializeToken()
// This will swap the ecash contained in the token and return your new proofs
let proofs = try await mint.receive(token: token)
```

#### Melting ecash

```swift
let meltQuoteRequest = Bolt11.RequestMeltQuote(unit: "sat", request: q2.request, options: nil)
let meltQ = try await mint.getQuote(quoteRequest: meltQuoteRequest)
let result = try await mint.melt(quote: meltQ, proofs: proofs)
// result.change is a list of proofs if you overpay on the melt quote
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
