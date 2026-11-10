# Comparison

Paying N recipients 0.01 ether each, with huff-neo-disperse and similar contracts.

| Contract | Pays with | Transactions | Recipient's code runs | Recipient can revert the batch | Locked to a block | Refunds the rest |
|---|---|:-:|:-:|:-:|:-:|:-:|
| huff-neo-disperse, accounts | `CALL` | 1 | has none | no | yes | yes |
| huff-neo-disperse, contracts | forwarder, `SELFDESTRUCT` | 1 | no | no | yes | yes |
| [disperse.app](https://github.com/omniaprotocol/disperse.app) | `transfer`, 2,300 gas | 1 | 2,300 gas | yes | no | yes |
| helix [PaymentForwarder](https://github.com/gattaca-com/helix/blob/main/contracts/src/PaymentForwarder.huff) | `SELFDESTRUCT` | N | no | — | yes | — |
| helix [SlotLockedDisperser](https://github.com/gattaca-com/helix/pull/480) | `CALL`, all gas, storage lock | 1 | all gas | yes | yes | yes |
| [Titan](https://etherscan.io/address/0xFeEeEEEAEA9b3cE71Ce8A252aAa11D2dC439CC69) | [forwarder](https://etherscan.io/address/0xFeEeEEE0e9C10f0484111144Ba82788E0B550D91), `SELFDESTRUCT` | 1 | no | no | yes | to the first recipient |

huff-neo-disperse checks each recipient with `EXTCODESIZE` and can mix both in one batch. Titan pays every
recipient through its forwarder, also an account, except the first, which takes what is left.

## Gas

Total `gasUsed` of the transactions. **Bold** is the cheapest.

**Existing accounts**

| Recipients | huff-neo-disperse | disperse.app | PaymentForwarder | SlotLockedDisperser | Titan |
|-----------:|------------------:|-------------:|-----------------:|--------------------:|------:|
| 1 | 29,031 | 32,060 | **28,806** | 42,449 | 28,837 |
| 2 | **38,748** | 41,982 | 57,612 | 50,204 | 46,058 |
| 3 | **48,439** | 51,904 | 86,418 | 57,958 | 60,753 |
| 4 | **58,130** | 61,826 | 115,224 | 65,712 | 75,448 |
| 5 | **67,821** | 71,748 | 144,018 | 73,467 | 90,143 |
| 10 | **116,276** | 121,370 | 288,060 | 120,398 | 163,618 |
| 25 | **261,857** | 270,500 | 720,450 | 266,093 | 384,343 |
| 100 | **989,654** | 1,015,550 | 2,881,788 | 993,968 | 1,487,368 |

**New accounts**, which have never held ETH and cost 25,000 gas more per payment

| Recipients | huff-neo-disperse | disperse.app | PaymentForwarder | SlotLockedDisperser | Titan |
|-----------:|------------------:|-------------:|-----------------:|--------------------:|------:|
| 1 | 54,031 | 57,060 | **53,806** | 62,449 | 53,837 |
| 2 | **88,748** | 91,982 | 107,612 | 92,854 | 96,058 |
| 3 | **123,439** | 126,904 | 161,418 | 127,547 | 135,753 |
| 4 | **158,130** | 161,826 | 215,224 | 162,240 | 175,448 |
| 5 | **192,821** | 196,748 | 269,030 | 196,933 | 215,143 |
| 10 | **366,276** | 371,370 | 538,060 | 370,398 | 413,618 |
| 25 | **886,857** | 895,500 | 1,345,450 | 891,093 | 1,009,343 |
| 100 | **3,489,654** | 3,515,550 | 5,381,788 | 3,493,968 | 3,987,368 |

**Contracts** that accept ETH. disperse.app and SlotLockedDisperser run their code, so one that rejects ETH
reverts the batch. huff-neo-disperse and Titan do not, for about 5,000 gas more per contract.

| Recipients | huff-neo-disperse | disperse.app | PaymentForwarder | SlotLockedDisperser | Titan |
|-----------:|------------------:|-------------:|-----------------:|--------------------:|------:|
| 1 | 29,043 | 32,060 | **28,806** | 42,449 | 28,837 |
| 2 | 46,262 | **41,982** | 57,612 | 50,204 | 46,058 |
| 3 | 60,967 | **51,904** | 86,418 | 57,958 | 60,753 |
| 4 | 75,672 | **61,826** | 115,224 | 65,712 | 75,448 |
| 5 | 90,377 | **71,748** | 144,030 | 73,467 | 90,143 |
| 10 | 163,902 | 121,370 | 288,060 | **120,398** | 163,618 |
| 25 | 384,777 | 270,500 | 720,450 | **266,093** | 384,343 |
| 100 | 1,488,540 | 1,015,550 | 2,881,572 | **993,956** | 1,487,356 |

**Each extra recipient**, from 10 to 100

| Paid to | huff-neo-disperse | disperse.app | PaymentForwarder | SlotLockedDisperser | Titan |
|---------|------------------:|-------------:|-----------------:|--------------------:|------:|
| existing accounts | **9,704** | 9,935 | 28,819 | 9,706 | 14,708 |
| new accounts | **34,704** | 34,935 | 53,819 | 34,706 | 39,708 |
| contracts | 14,718 | 9,935 | 28,817 | **9,706** | 14,708 |

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
| Titan | ~5,000 gas more for every recipient, also an account: the `CALL` to the forwarder plus its `SELFDESTRUCT`; the first with its own `SELFDESTRUCT` |
| any | an [access list](https://eips.ethereum.org/EIPS/eip-2930) saves 100 gas per address, not used here |

## Method

`script/compare_gas.py` sends the payments as real transactions to a local anvil node with Fusaka's rules
(`--hardfork osaka`), so the numbers include each transaction's 21,000 gas and calldata. disperse.app and
Titan's disperser and forwarder run their mainnet bytecode at their mainnet addresses. helix's contracts are
fetched at a pinned commit and compiled with hnc 1.7.1.

```bash
python3 script/compare_gas.py
```
