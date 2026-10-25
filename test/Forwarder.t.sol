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

/// Tests the forwarder, deployed with CREATE2 through the deterministic deployer as on a real chain
contract ForwarderTest is Test {
    using HuffNeoConfig for HuffConfig;

    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address constant FORWARDER = 0x6d93D11e4C74e195DEe61693650D4FabCB6D6013;

    address bob = makeAddr("bob");

    function setUp() public {
        bytes memory forwarder = HuffNeoDeployer.config().creation_code("src/Forwarder.huff");
        (bool ok,) = CREATE2_DEPLOYER.call(abi.encodePacked(bytes32(0), forwarder));
        require(ok, "forwarder not deployed");
    }

    function forward(uint256 value, bytes memory data) internal returns (bool ok) {
        (ok,) = FORWARDER.call{value: value}(data);
    }

    function test_sendsTheValueToTheAddress() public {
        assertTrue(forward(1 ether, abi.encode(bob)));
        assertEq(bob.balance, 1 ether);
        assertEq(FORWARDER.balance, 0);
    }

    /// Only the lower 20 bytes of the word are the address, so Disperse can pass its entries as they are
    function test_ignoresTheUpper12Bytes() public {
        assertTrue(forward(1 ether, abi.encode(uint256(type(uint96).max) << 160 | uint160(bob))));
        assertEq(bob.balance, 1 ether);
    }

    /// ETH the forwarder held before, for example forced in by a SELFDESTRUCT, goes along with the payment
    function test_sendsAllItHolds() public {
        vm.deal(FORWARDER, 5);
        assertTrue(forward(1 ether, abi.encode(bob)));
        assertEq(bob.balance, 1 ether + 5);
    }

    function test_paysARecipientThatRejects() public {
        address rejecter = address(new Rejecter());
        assertTrue(forward(1 ether, abi.encode(rejecter)));
        assertEq(rejecter.balance, 1 ether);
    }

    /// Without calldata, the address is zero
    function test_paysTheZeroAddressWithoutCalldata() public {
        uint256 before = address(0).balance;
        assertTrue(forward(1 ether, ""));
        assertEq(address(0).balance, before + 1 ether);
    }

    /// SELFDESTRUCT moves only the balance since Cancun, so the forwarder works for the next payment
    function test_keepsItsCode() public {
        assertTrue(forward(1 ether, abi.encode(bob)));
        assertTrue(forward(1 ether, abi.encode(bob)));
        assertEq(bob.balance, 2 ether);
        assertEq(FORWARDER.code, hex"5f35ff");
    }

    function testFuzz_sendsTheValueToAnyAddress(address recipient, uint96 value) public {
        vm.assume(recipient != FORWARDER);
        uint256 before = recipient.balance;
        assertTrue(forward(value, abi.encode(recipient)));
        assertEq(recipient.balance, before + value);
        assertEq(FORWARDER.balance, 0);
    }
}
