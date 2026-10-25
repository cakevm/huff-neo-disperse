// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {HuffConfig, HuffNeoConfig, HuffNeoDeployer} from "foundry-huff-neo/HuffNeoDeployer.sol";

/// Rejects every payment that runs its code
contract Rejecter {
    receive() external payable {
        revert();
    }
}

/// Calls back into Disperse with an empty batch for this block, which would take the value left in Disperse
/// through the refund if it ran
contract ReEnterer {
    receive() external payable {
        (bool ok,) = msg.sender.call(abi.encodePacked(uint32(block.timestamp)));
        ok;
    }
}

/// Tests Disperse and the forwarder, deployed the way they are on a real chain: the forwarder with
/// CREATE2 through the deterministic deployer, Disperse with HuffNeoDeployer.
contract DisperseTest is Test {
    using HuffNeoConfig for HuffConfig;

    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address constant FORWARDER = 0x6d93D11e4C74e195DEe61693650D4FabCB6D6013;
    uint32 constant TIMESTAMP = 1700000000;

    address disperse;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        bytes memory forwarder = HuffNeoDeployer.config().creation_code("src/Forwarder.huff");
        (bool ok,) = CREATE2_DEPLOYER.call(abi.encodePacked(bytes32(0), forwarder));
        require(ok, "forwarder not deployed");
        disperse = HuffNeoDeployer.deploy("src/Disperse.huff");
        vm.warp(TIMESTAMP);
    }

    /// An entry pays amount wei to recipient
    function entry(uint96 amount, address recipient) internal pure returns (bytes32) {
        return bytes32(uint256(amount) << 160 | uint160(recipient));
    }

    function batch(bytes32[] memory entries) internal pure returns (bytes memory data) {
        for (uint256 i; i < entries.length; i++) {
            data = bytes.concat(data, entries[i]);
        }
        return bytes.concat(data, bytes4(TIMESTAMP));
    }

    function pair(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory entries) {
        entries = new bytes32[](2);
        entries[0] = a;
        entries[1] = b;
    }

    function pay(uint256 value, bytes memory data) internal returns (bool ok) {
        (ok,) = disperse.call{value: value}(data);
    }

    function test_forwarderIsAtTheAddressBuiltIntoDisperse() public view {
        assertEq(FORWARDER.code, hex"5f35ff");
    }

    function test_paysAccounts() public {
        assertTrue(pay(1.25 ether, batch(pair(entry(1 ether, alice), entry(0.25 ether, bob)))));
        assertEq(alice.balance, 1 ether);
        assertEq(bob.balance, 0.25 ether);
        assertEq(disperse.balance, 0);
    }

    function test_paysContractsWithoutRunningTheirCode() public {
        address first = address(new Rejecter());
        address second = address(new Rejecter());
        assertTrue(pay(1.25 ether, batch(pair(entry(1 ether, first), entry(0.25 ether, second)))));
        assertEq(first.balance, 1 ether);
        assertEq(second.balance, 0.25 ether);
    }

    /// An EIP-7702 delegated account has the 23-byte delegation as code, so it is forced and its delegated code,
    /// which rejects every payment, does not run
    function test_paysADelegatedAccountWithoutRunningItsCode() public {
        (address account, uint256 key) = makeAddrAndKey("delegated");
        vm.signAndAttachDelegation(address(new Rejecter()), key);
        assertEq(account.code.length, 23);
        (bool ok,) = account.call{value: 1}("");
        assertFalse(ok, "a CALL runs the delegated code");

        assertTrue(pay(1.25 ether, batch(pair(entry(1 ether, alice), entry(0.25 ether, account)))));
        assertEq(account.balance, 0.25 ether);
    }

    /// The refund reaches this test contract, which has no receive function, since SELFDESTRUCT runs no code
    function test_refundsWhatIsLeft() public {
        uint256 before = address(this).balance;
        assertTrue(pay(2 ether, batch(pair(entry(1 ether, alice), entry(0.25 ether, address(new Rejecter()))))));
        assertEq(address(this).balance, before - 1.25 ether);
        assertEq(disperse.balance, 0);
    }

    /// The re-entering contract comes last, so it is paid first, while Alice's 1 ether is still in Disperse
    function test_aContractCannotReEnter() public {
        address reEnterer = address(new ReEnterer());
        assertTrue(pay(1.25 ether, batch(pair(entry(1 ether, alice), entry(0.25 ether, reEnterer)))));
        assertEq(alice.balance, 1 ether);
        assertEq(reEnterer.balance, 0.25 ether);
        assertEq(disperse.balance, 0);
    }

    /// Without the forwarder, a contract taking exactly what is left is still paid: by Disperse's own SELFDESTRUCT
    function test_paysTheExactRestWithItsOwnSelfdestruct() public {
        vm.etch(FORWARDER, "");
        address rejecter = address(new Rejecter());
        assertTrue(pay(1 ether, bytes.concat(entry(1 ether, rejecter), bytes4(TIMESTAMP))));
        assertEq(rejecter.balance, 1 ether);
        assertEq(disperse.balance, 0);
    }

    function test_revertsWhenTheValueIsShortForAnAccount() public {
        assertFalse(pay(1.25 ether - 1, batch(pair(entry(1 ether, alice), entry(0.25 ether, bob)))));
    }

    /// The second contract comes last, so it is paid first; the first then no longer fits
    function test_revertsWhenTheValueIsShortForAContract() public {
        address first = address(new Rejecter());
        address second = address(new Rejecter());
        assertFalse(pay(1 ether, batch(pair(entry(1 ether, first), entry(0.25 ether, second)))));
    }

    /// A precompile has no code, so it gets a CALL with the 2,300 gas stipend and the entry as input;
    /// ecrecover needs 3,000 gas, so its payment fails
    function test_revertsWhenAPrecompilePaymentFails() public {
        assertFalse(pay(1.25 ether, batch(pair(entry(1 ether, alice), entry(0.25 ether, address(1))))));
    }

    /// The SHA-256 precompile needs only 72 gas, so it is paid
    function test_paysAPrecompileThatAccepts() public {
        assertTrue(pay(1.25 ether, batch(pair(entry(1 ether, alice), entry(0.25 ether, address(2))))));
        assertEq(address(2).balance, 0.25 ether);
    }

    function test_revertsInAnotherBlock() public {
        bytes memory data = batch(pair(entry(1 ether, alice), entry(0, bob)));
        vm.warp(TIMESTAMP + 12);
        assertFalse(pay(1 ether, data));
    }

    function test_revertsOnAPartialEntry() public {
        assertFalse(pay(1 ether, bytes.concat(entry(1 ether, alice), bytes1(0), bytes4(TIMESTAMP))));
    }

    /// With 0 to 3 bytes, the end underflows, and the timestamp read past the calldata is 0
    function test_revertsOnCalldataShorterThanATimestamp() public {
        bytes memory timestamp = abi.encodePacked(TIMESTAMP);
        for (uint256 length; length < 4; length++) {
            bytes memory data = new bytes(length);
            for (uint256 i; i < length; i++) {
                data[i] = timestamp[i];
            }
            assertFalse(pay(1, data));
        }
    }

    function test_revertsWithoutATimestamp() public {
        assertFalse(pay(1 ether, abi.encodePacked(entry(1 ether, alice))));
    }

    /// SELFDESTRUCT moves only the balance since Cancun, so both contracts work for the next batch
    function test_keepsItsCodeAfterABatch() public {
        address rejecter = address(new Rejecter());
        assertTrue(pay(1 ether, batch(pair(entry(1 ether, rejecter), entry(0, bob)))));
        assertTrue(pay(1 ether, batch(pair(entry(1 ether, rejecter), entry(0, bob)))));
        assertEq(rejecter.balance, 2 ether);
        assertEq(FORWARDER.code, hex"5f35ff");
        assertGt(disperse.code.length, 0);
    }

    /// Any two recipients, with or without code, are paid exactly, and the rest of the value is refunded
    function testFuzz_paysAndRefunds(uint64 a, uint64 b, bool codeA, bool codeB, uint64 extra, uint256 seed) public {
        address first = address(uint160(uint256(keccak256(abi.encode(seed, 1)))));
        address second = address(uint160(uint256(keccak256(abi.encode(seed, 2)))));
        if (codeA) vm.etch(first, hex"5f5ffd");
        if (codeB) vm.etch(second, hex"5f5ffd");
        uint256 before = address(this).balance;

        assertTrue(pay(uint256(a) + b + extra, batch(pair(entry(a, first), entry(b, second)))));
        assertEq(first.balance, a);
        assertEq(second.balance, b);
        assertEq(address(this).balance, before - a - b);
        assertEq(disperse.balance, 0);
    }

    /// Any two recipients, with or without code, revert the batch when the value is short by any amount
    function testFuzz_revertsWhenTheValueIsShort(
        uint64 a,
        uint64 b,
        bool codeA,
        bool codeB,
        uint256 short,
        uint256 seed
    ) public {
        uint256 sum = uint256(a) + b;
        vm.assume(sum > 0);
        short = bound(short, 1, sum);
        address first = address(uint160(uint256(keccak256(abi.encode(seed, 1)))));
        address second = address(uint160(uint256(keccak256(abi.encode(seed, 2)))));
        if (codeA) vm.etch(first, hex"5f5ffd");
        if (codeB) vm.etch(second, hex"5f5ffd");

        assertFalse(pay(sum - short, batch(pair(entry(a, first), entry(b, second)))));
    }

    /// A batch paying 0.01 ether to each of n new accounts, or to n contracts
    function batchOf(uint256 n, bool contracts) internal returns (bytes memory) {
        bytes32[] memory entries = new bytes32[](n);
        for (uint256 i; i < n; i++) {
            address recipient = address(uint160(0x10000 + i));
            if (contracts) vm.etch(recipient, hex"00");
            entries[i] = entry(0.01 ether, recipient);
        }
        return batch(entries);
    }

    /// Records the gas of one batch in snapshots/DisperseTest.json
    function snapshotBatch(string memory name, uint256 n, bool contracts) internal {
        bytes memory data = batchOf(n, contracts);
        assertTrue(pay(n * 0.01 ether, data));
        vm.snapshotGasLastFrame(name);
    }

    function test_gasAccounts1() public {
        snapshotBatch("accounts_1", 1, false);
    }

    function test_gasAccounts10() public {
        snapshotBatch("accounts_10", 10, false);
    }

    function test_gasAccounts100() public {
        snapshotBatch("accounts_100", 100, false);
    }

    function test_gasContracts1() public {
        snapshotBatch("contracts_1", 1, true);
    }

    function test_gasContracts10() public {
        snapshotBatch("contracts_10", 10, true);
    }

    function test_gasContracts100() public {
        snapshotBatch("contracts_100", 100, true);
    }
}
