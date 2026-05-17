# ``CashuSwift``

A Swift implementation of the Cashu protocol for building ecash wallets and applications.

## Overview

CashuSwift provides a comprehensive set of tools for working with Cashu ecash mints.

Each payment-method backend the mint exposes lives in its own namespace —
``CashuSwift/Bolt11`` for NUT-23 Lightning invoices, ``CashuSwift/Bolt12`` for NUT-25
Lightning offers, and ``CashuSwift/Generic`` as an escape hatch for any other
method the mint advertises but the library has no first-class support for.

## Topics

### Essentials

- ``CashuSwift``
- ``Mint``
- ``Proof``
- ``Token``

### Payment Methods

- ``CashuSwift/Bolt11``
- ``CashuSwift/Bolt12``
- ``CashuSwift/Generic``
- ``CashuSwift/PaymentMethodID``

### Operations

- ``loadMint(url:type:)``
- ``send(inputs:mint:amount:seed:memo:lockToPublicKey:)``
- ``receive(token:of:mint:seed:privateKey:)``
- ``swap(inputs:with:amount:seed:preferredDistribution:)``
- ``restore(mint:with:batchSize:)``

### Models

- ``Output``
- ``Promise``
- ``DLEQ``
- ``MintQuoteRequest``
- ``MintQuoteResponse``
- ``MeltQuoteRequest``
- ``MeltQuoteResponse``
- ``Keyset``
- ``MintInfo``
- ``SpendingCondition``

### Errors

- ``CashuError``

### Cryptography

- ``Crypto``
