# Huff Neo Disperse

[![CI status](https://github.com/cakevm/huff-neo-disperse/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/cakevm/huff-neo-disperse/actions/workflows/ci.yaml)

Sends ETH to many addresses in one transaction, written in Huff with [huff-neo](https://github.com/cakevm/huff-neo). An account without code is paid with a `CALL`. A contract is paid through a forwarder's `SELFDESTRUCT`, so its code never runs and it cannot reject the payment or re-enter. As always, you are responsible for the contracts you deploy.

| Total gas | 1 account | 5 accounts | 25 accounts | 25 contracts |
|---|---:|---:|---:|---:|
| **huff-neo-disperse** | 29,031 | **67,821** | **261,641** | 384,777 |
| [disperse.app](https://github.com/omniaprotocol/disperse.app) | 32,060 | 71,748 | 270,200 | 270,500 |
| helix [PaymentForwarder](https://github.com/gattaca-com/helix/blob/main/contracts/src/PaymentForwarder.huff), one transaction each | **28,806** | 144,030 | 720,354 | 720,450 |
| helix [SlotLockedDisperser](https://github.com/gattaca-com/helix/pull/480) | 42,449 | 73,467 | 266,093 | **266,093** |

The recipients already exist, and the contracts accept ETH. disperse.app and SlotLockedDisperser run a contract's code, so one that rejects ETH reverts their whole batch. huff-neo-disperse pays about 5,000 gas more per contract so that its code never runs.

More numbers, new accounts and guarantees in [COMPARISON.md](./COMPARISON.md).

## Calldata

A batch is a list of 32-byte entries followed by the `uint32` timestamp of the block it is made for:

| Bytes | Field | |
|---:|---|---|
| 12 | amount | in wei, up to 2⁹⁶ − 1, about 79 billion ETH |
| 20 | recipient | |
| 4 | timestamp | once, after the last entry; the batch reverts in any other block |

Each entry is one 32-byte word, read with a single `CALLDATALOAD`.

For example 1 ether to `0xa11ce` and 0.25 ether to `0xb0b`, in the block at `1700000000`:
```
  amount (wei)             recipient
  ------------------------ ----------------------------------------
0x000000000de0b6b3a7640000 00000000000000000000000000000000000a11ce   1 ether
  0000000003782dace9d90000 0000000000000000000000000000000000000b0b   0.25 ether
  6553f100                                                            timestamp 1700000000
```

Without the spaces and line breaks, this is the calldata:
```bash
cast send <DISPERSE> 0x000000000de0b6b3a764000000000000000000000000000000000000000a11ce0000000003782dace9d900000000000000000000000000000000000000000b0b6553f100 --value 1.25ether
```

The recipient decides how it is paid, checked with `EXTCODESIZE`, which costs about 100 gas:

| Recipient | Payment | Its code |
|---|---|---|
| account without code | `CALL` | none to run |
| contract, or EIP-7702 delegated account | through the forwarder's `SELFDESTRUCT`, ~5,000 gas more | never runs |

If any payment fails, the batch reverts. No recipient's code runs, so that only happens when the value is short, or for a precompile that needs more than the 2,300 gas stipend or rejects the entry as input, such as ecrecover (`0x01`).

The check happens at payment time, so front-running cannot turn it against the batch. A flag set by the caller could: a recipient marked for a `CALL` could deploy code or set an EIP-7702 delegation first, then revert the batch. With `EXTCODESIZE`, a recipient that gains code is forced, which only costs about 5,000 gas more, and one that loses it, by clearing a delegation, has no code to run.

Send at least the sum of the amounts; anything more is refunded. The first entry is paid last: when it takes exactly what is left, `Disperse` pays it with its own `SELFDESTRUCT`, which is cheaper than a `CALL` and runs no code. The batch reverts in any other block, so a reorg or a missed slot cannot replay it.

An [access list](https://eips.ethereum.org/EIPS/eip-2930) with the recipients and the forwarder saves 100 gas per address, for example with `cast send --access-list`.

## Deployment

Both contracts are deployed with CREATE2 through the [deterministic deployer](https://github.com/Arachnid/deterministic-deployment-proxy), at the same address on every chain. Deploy the forwarder first:
```bash
forge script script/DeployForwarder.s.sol --rpc-url <RPC_URL> --private-key <KEY> --broadcast
forge script script/DeployDisperse.s.sol --rpc-url <RPC_URL> --private-key <KEY> --broadcast
```

Both are deployed to Ethereum mainnet:

| Contract | Address |
|---|---|
| Forwarder | [`0xF000000000Ae9a463979125d6C3df571d9853200`](https://etherscan.io/address/0xF000000000Ae9a463979125d6C3df571d9853200) |
| Disperse | [`0xD000000000D826d1525e0D209D7ac8C3b15D2C47`](https://etherscan.io/address/0xD000000000D826d1525e0D209D7ac8C3b15D2C47) |

Disperse pays contracts through the forwarder at its built-in address, so only use it on a chain where the forwarder is deployed. `DeployDisperse.s.sol` refuses to run without it.

## Testing

The Huff tests use hnc's test runner, which is still experimental, so the Solidity tests cover the same behavior through a real deployment.

```bash
forge fmt
forge snapshot
for file in test/*.t.huff; do hnc $file test || exit 1; done
python3 script/compare_gas.py
```

## Acknowledgements

- [disperse.app](https://github.com/omniaprotocol/disperse.app), for paying many addresses in one transaction
- helix's [PaymentForwarder](https://github.com/gattaca-com/helix/blob/main/contracts/src/PaymentForwarder.huff), for paying with `SELFDESTRUCT` and locking a payment to a block
- [EIP-5920](https://eips.ethereum.org/EIPS/eip-5920), the proposed `PAY` opcode, which would make the forwarder unnecessary

## License

This project is dual licensed under [Apache 2.0](./LICENSE-APACHE) or [MIT](./LICENSE-MIT), at your option.
