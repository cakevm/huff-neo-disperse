#!/usr/bin/env python3
"""Compares the gas of paying N recipients with huff-neo-disperse and similar contracts.

Starts a local anvil node and sends the same payments through each contract as real transactions:
- huff-neo-disperse, with the forwarder deployed the way it is on a real chain (CREATE2 through the
  deterministic deployer)
- disperse.app, with its mainnet bytecode at its mainnet address
- helix's PaymentForwarder, which pays one recipient per transaction, so N recipients take N
  transactions
- helix's SlotLockedDisperser (open pull request), which pays N recipients with CALL

helix's contracts are fetched from GitHub at a pinned commit and compiled with hnc. Prints a Markdown
table of the total gas of each.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

RPC = "http://127.0.0.1:8599"
# anvil's first default account
KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
CREATE2_DEPLOYER = "0x4e59b44847b379578588920cA78FbF26c0B4956C"
DISPERSE_APP = "0xD152f549545093347A162Dce210e7293f1452150"
HELIX = "https://raw.githubusercontent.com/gattaca-com/helix"
PAYMENT_FORWARDER = f"{HELIX}/644e3191c184e65cafe40e3219b4cdcef3b68967/contracts/src/PaymentForwarder.huff"
SLOT_LOCKED_DISPERSER = f"{HELIX}/d795384b9078678b5f97ee4802a7a1b56fe210eb/contracts/src/SlotLockedDisperser.huff"
AMOUNT = 10**16  # 0.01 ether
COUNTS = (1, 2, 3, 4, 5, 10, 25, 100)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, cwd=ROOT).stdout.strip()


def send(to, value, data):
    receipt = json.loads(run("cast", "send", "--rpc-url", RPC, "--private-key", KEY, "--json", "--value", str(value), to, data))
    assert receipt["status"] == "0x1", receipt
    return int(receipt["gasUsed"], 16)


def deploy(creation_code):
    receipt = json.loads(run("cast", "send", "--rpc-url", RPC, "--private-key", KEY, "--json", "--create", "0x" + creation_code))
    return receipt["contractAddress"]


def compile_remote(url, directory):
    path = os.path.join(directory, os.path.basename(url))
    with urllib.request.urlopen(url) as response, open(path, "wb") as f:
        f.write(response.read())
    return run("hnc", path, "-b")


def next_block_timestamp():
    """Sets the timestamp of the next block, the one a payment is made for"""
    timestamp = int(run("cast", "block", "--rpc-url", RPC, "latest", "--field", "timestamp")) + 12
    run("cast", "rpc", "--rpc-url", RPC, "evm_setNextBlockTimestamp", str(timestamp))
    return timestamp


def pay_huff_neo_disperse(contract, addrs):
    entries = "".join(f"{AMOUNT:024x}{a[2:]}" for a in addrs)
    return send(contract, AMOUNT * len(addrs), f"0x{entries}{next_block_timestamp():08x}")


def give_code(addrs):
    """Makes the recipients contracts that accept ETH, with a STOP as their code"""
    for a in addrs:
        run("cast", "rpc", "--rpc-url", RPC, "anvil_setCode", a, "0x00")


def pay_disperse_app(contract, addrs):
    data = run("cast", "calldata", "disperseEther(address[],uint256[])", f"[{','.join(addrs)}]", f"[{','.join([str(AMOUNT)] * len(addrs))}]")
    return send(contract, AMOUNT * len(addrs), data)


def pay_payment_forwarder(contract, addrs):
    return sum(send(contract, AMOUNT, f"0x{next_block_timestamp():08x}{a[2:]}") for a in addrs)


def pay_slot_locked_disperser(contract, addrs):
    entries = "".join(f"{a[2:]}{AMOUNT:064x}" for a in addrs)
    return send(contract, AMOUNT * len(addrs), f"0x{next_block_timestamp():08x}{entries}")


def main():
    anvil = subprocess.Popen(["anvil", "--port", "8599", "--hardfork", "osaka", "--silent"])
    try:
        time.sleep(1.5)
        forwarder_init = run("hnc", "src/Forwarder.huff", "-b")
        forwarder = run("cast", "compute-address", CREATE2_DEPLOYER, "--salt", "0x" + "00" * 32, "--init-code", "0x" + forwarder_init).split()[-1]
        send(CREATE2_DEPLOYER, 0, "0x" + "00" * 32 + forwarder_init)
        assert run("cast", "code", "--rpc-url", RPC, forwarder) == "0x" + run("hnc", "src/Forwarder.huff", "-r")

        with open(os.path.join(ROOT, "test/fixtures/disperse-app.hex")) as f:
            run("cast", "rpc", "--rpc-url", RPC, "anvil_setCode", DISPERSE_APP, f.read().strip())
        with tempfile.TemporaryDirectory() as directory:
            payment_forwarder = deploy(compile_remote(PAYMENT_FORWARDER, directory))
            slot_locked_disperser = deploy(compile_remote(SLOT_LOCKED_DISPERSER, directory))

        disperse = deploy(run("hnc", "src/Disperse.huff", "-b"))
        contracts = (
            ("huff-neo-disperse", pay_huff_neo_disperse, disperse),
            ("disperse.app", pay_disperse_app, DISPERSE_APP),
            ("PaymentForwarder", pay_payment_forwarder, payment_forwarder),
            ("SlotLockedDisperser", pay_slot_locked_disperser, slot_locked_disperser),
        )

        print("| Recipients | Paid to | " + " | ".join(name for name, _, _ in contracts) + " |")
        print("|-----------:|---------|" + "|".join("-" * (len(name) + 1) + ":" for name, _, _ in contracts) + "|")
        start = 0x10000
        for n in COUNTS:
            # Each contract pays its own addresses: new accounts, the same again as existing accounts, then
            # contracts, which always exist
            def fresh():
                nonlocal start
                batch = [[f"0x{start + c * n + i:040x}" for i in range(n)] for c in range(len(contracts))]
                start += len(contracts) * n
                return batch

            accounts, contract_recipients = fresh(), fresh()
            for addrs in contract_recipients:
                give_code(addrs)
            for label, batch in (("new accounts", accounts), ("existing accounts", accounts), ("contracts", contract_recipients)):
                gas = [pay(contract, a) for (_, pay, contract), a in zip(contracts, batch)]
                print(f"| {n} | {label} | " + " | ".join(f"{g:,}" for g in gas) + " |")
    finally:
        anvil.terminate()


if __name__ == "__main__":
    sys.exit(main())
