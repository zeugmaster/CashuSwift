# ``CashuSwift``

A Swift implementation of the Cashu protocol for building ecash wallets and applications.

## Overview

CashuSwift provides a comprehensive set of tools for working with Cashu ecash mints.

## Topics

### Essentials

- ``CashuSwift``
- ``Mint``
- ``Proof``
- ``Token``

### Operations

- ``loadMint(url:type:)``
- ``getQuote(mint:quoteRequest:)``
- ``issue(for:with:seed:preferredDistribution:)``
- ``send(inputs:mint:amount:seed:memo:lockToPublicKey:)``
- ``receive(token:of:mint:seed:privateKey:)``
- ``melt(with:mint:proofs:timeout:blankOutputs:)``
- ``swap(inputs:with:amount:seed:preferredDistribution:)``
- ``restore(mint:with:batchSize:)``

### Models

- ``Output``
- ``Promise`` 
- ``DLEQ``
- ``Quote``
- ``Keyset``
- ``MintInfo``
- ``SpendingCondition``

### Errors

- ``CashuError``

### Cryptography

- ``Crypto`` 
