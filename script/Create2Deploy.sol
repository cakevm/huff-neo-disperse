// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {HuffConfig, HuffNeoConfig, HuffNeoDeployer} from "foundry-huff-neo/HuffNeoDeployer.sol";

/// Deploys a contract with CREATE2 through the deterministic deployer, so it has the same address on
/// every chain. A contract that is already deployed is skipped.
abstract contract Create2Deploy is Script {
    using HuffNeoConfig for HuffConfig;

    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// The forwarder's address built into Disperse
    address constant FORWARDER = 0xF000000000Ae9a463979125d6C3df571d9853200;
    bytes32 constant FORWARDER_SALT = 0x0000000000000000000000000000000000000000ad32a01bdc3371059b2f5eab;

    address constant DISPERSE = 0xD000000000D826d1525e0D209D7ac8C3b15D2C47;
    bytes32 constant DISPERSE_SALT = 0x00000000000000000000000000000000000000005d3238a7d492cd06b4966918;

    function deploy(string memory file, bytes32 salt) internal returns (address addr) {
        bytes memory code = HuffNeoDeployer.config().creation_code(file);
        addr = vm.computeCreate2Address(salt, keccak256(code), CREATE2_DEPLOYER);
        if (addr.code.length > 0) {
            console.log("%s already deployed at %s", file, addr);
            return addr;
        }

        vm.broadcast();
        (bool ok,) = CREATE2_DEPLOYER.call(abi.encodePacked(salt, code));
        require(ok && addr.code.length > 0, "deployment failed");
        console.log("%s deployed at %s", file, addr);
    }
}
