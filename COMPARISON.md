# Comparison

Paying N recipients 0.01 ether each, with huff-neo-disperse and similar contracts.

| Contract | Pays with | Transactions | Recipient's code runs | Recipient can revert the batch | Locked to a block | Refunds the rest |
|---|---|:-:|:-:|:-:|:-:|:-:|
| huff-neo-disperse, accounts | `CALL` | 1 | has none | no | yes | yes |
| huff-neo-disperse, contracts | forwarder, `SELFDESTRUCT` | 1 | no | no | yes | yes |
| [disperse.app](https://github.com/omniaprotocol/disperse.app) | `transfer`, 2,300 gas | 1 | 2,300 gas | yes | no | yes |
| helix [PaymentForwarder](https://github.com/gattaca-com/helix/blob/main/contracts/src/PaymentForwarder.huff) | `SELFDESTRUCT` | N | no | — | yes | — |
| helix [SlotLockedDisperser](https://github.com/gattaca-com/helix/pull/480) | `CALL`, all gas, storage lock | 1 | all gas | yes | yes | yes |

huff-neo-disperse checks each recipient with `EXTCODESIZE` and can mix both in one batch.

## Gas

Total `gasUsed` of the transactions. **Bold** is the cheapest.

**Existing accounts**

| Recipients | huff-neo-disperse | disperse.app | PaymentForwarder | SlotLockedDisperser |
|-----------:|------------------:|-------------:|-----------------:|--------------------:|
| 1 | 29,031 | 32,060 | **28,806** | 42,449 |
| 2 | **38,748** | 41,982 | 57,612 | 50,204 |
| 3 | **48,439** | 51,904 | 86,418 | 57,958 |
| 4 | **58,130** | 61,826 | 115,224 | 65,712 |
| 5 | **67,821** | 71,748 | 144,030 | 73,467 |
| 10 | **116,276** | 121,370 | 288,060 | 120,398 |
| 25 | **261,641** | 270,200 | 720,354 | 266,093 |
| 100 | **989,666** | 1,015,538 | 2,881,788 | 993,956 |

**New accounts**, which have never held ETH and cost 25,000 gas more per payment

| Recipients | huff-neo-disperse | disperse.app | PaymentForwarder | SlotLockedDisperser |
|-----------:|------------------:|-------------:|-----------------:|--------------------:|
| 1 | 54,031 | 57,060 | **53,806** | 62,449 |
| 2 | **88,748** | 91,982 | 107,612 | 92,854 |
| 3 | **123,439** | 126,904 | 161,418 | 127,547 |
| 4 | **158,130** | 161,826 | 215,224 | 162,240 |
| 5 | **192,821** | 196,748 | 269,030 | 196,933 |
| 10 | **366,276** | 371,370 | 538,060 | 370,398 |
| 25 | **886,641** | 895,200 | 1,345,366 | 891,093 |
| 100 | **3,489,666** | 3,515,538 | 5,381,776 | 3,493,956 |

**Contracts** that accept ETH. disperse.app and SlotLockedDisperser run their code, so one that rejects ETH
reverts the batch. huff-neo-disperse does not, for about 5,000 gas more per contract.

| Recipients | huff-neo-disperse | disperse.app | PaymentForwarder | SlotLockedDisperser |
|-----------:|------------------:|-------------:|-----------------:|--------------------:|
| 1 | 29,043 | 32,060 | **28,806** | 42,449 |
| 2 | 46,262 | **41,982** | 57,612 | 50,204 |
| 3 | 60,967 | **51,904** | 86,418 | 57,958 |
| 4 | 75,672 | **61,826** | 115,224 | 65,712 |
| 5 | 90,377 | **71,748** | 144,030 | 73,467 |
| 10 | 163,902 | 121,370 | 288,060 | **120,398** |
| 25 | 384,777 | 270,500 | 720,450 | **266,093** |
| 100 | 1,488,552 | 1,015,550 | 2,881,764 | **993,968** |

**Each extra recipient**, from 10 to 100

| Paid to | huff-neo-disperse | disperse.app | PaymentForwarder | SlotLockedDisperser |
|---------|------------------:|-------------:|-----------------:|--------------------:|
| existing accounts | **9,704** | 9,935 | 28,819 | 9,706 |
| new accounts | **34,704** | 34,935 | 53,819 | 34,706 |
| contracts | 14,718 | 9,935 | 28,819 | **9,706** |

## Why

Most of a payment is fixed by the EVM: 9,000 gas to send value, 2,600 for a cold account, 25,000 for a new one.

| Contract | Cost besides the payment |
|---|---|
| huff-neo-disperse, accounts | 32 bytes of calldata, ~100 gas for `EXTCODESIZE` and a few opcodes |
| huff-neo-disperse, contracts | ~5,000 gas more: the `CALL` to the forwarder plus its `SELFDESTRUCT` |
| huff-neo-disperse, last payment | its own `SELFDESTRUCT` when it takes exactly what is left: ~1,800 gas less for an account, ~9,300 for a contract |
| disperse.app | 64 bytes of ABI-encoded calldata per recipient |
| PaymentForwarder | a 21,000 gas transaction per recipient, but no `CALL` |
| SlotLockedDisperser | a storage lock per batch, refunded up to a fifth of the gas used |
| any | an [access list](https://eips.ethereum.org/EIPS/eip-2930) saves 100 gas per address, not used here |

## Method

`script/compare_gas.py` sends the payments as real transactions to a local anvil node with Fusaka's rules
(`--hardfork osaka`), so the numbers include each transaction's 21,000 gas and calldata. disperse.app runs
its mainnet bytecode. helix's contracts are fetched at a pinned commit and compiled with hnc 1.7.1.

```bash
python3 script/compare_gas.py
```
