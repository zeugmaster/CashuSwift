# Onchain interoperability tests

Run from the repository root with Docker Compose and the Swift toolchain installed:

```sh
Tests/OnchainRegtest/run.sh
```

The script starts disposable containers, runs `OnchainRegtestTests`, and removes
the containers and their test volumes on exit. It refuses to reuse existing
containers in its `cashuswift-onchain-regtest` project. Ports 19338 (mint) and
19443 (Bitcoin RPC) must be free; both bind only to localhost. The fixed RPC
credentials and public mnemonics are test fixtures. The suite checks that Core
reports `regtest` before sending coins or mining blocks.

Pinned dependencies:

- [CDK 0.18.0](https://github.com/cashubtc/cdk/releases/tag/v0.18.0), including BDK,
  image digest `sha256:fd938da187fb9fce82627ced6d419e675dbd6db5f0d50dc6930b1f6e18c359f0`.
- Bitcoin Core 29.0, image digest
  `sha256:a6aa8a9e349b4108d13c558dbe43064057bd7b6474b858966884f9cb95b7ed78`.
- [NUT-30 baseline](https://github.com/cashubtc/nuts/blob/f364a04162febbb8e860a3f121cd32d3d472cb44/30.md).

Coverage includes the two-confirmation threshold, individually undersized UTXOs,
repeated deposits, partial issuance with current NUT-20 signatures, verification
of actual mint DLEQ proofs, multiple withdrawal fee choices, asynchronous
broadcast/confirmation, serialized operation contexts, and idempotent change
recovery. Offline tests separately cover malicious responses, transport failures,
stale accounting, keyset rotation, and lost mint responses.

CDK 0.18 acknowledges a melt with `PENDING` and a null `selected_fee_index` before
its background worker stores the choice. CashuSwift retains the wallet's choice
in the context and validates it whenever returned; `PAID` requires a matching
index. The decoder also accepts an empty unbroadcast `outpoint` as absent, as
the reference CDK decoder does. These compatibility cases do not credit funds
or permit a second submission.

This release reports the outpoint at settlement, so the integration test checks
Bitcoin Core's mempool independently before mining the withdrawal's confirmations,
then binds the settled quote's outpoint to that transaction.

Normal `swift test` runs skip this integration suite. With
`CASHUSWIFT_ONCHAIN_REGTEST=1`, unavailable services are failures. For CI, invoke
the script in a dedicated job and retain its output; a skipped local test is not
integration coverage. Other existing integration suites use separate hosted
Lightning test services and are not part of this harness.
