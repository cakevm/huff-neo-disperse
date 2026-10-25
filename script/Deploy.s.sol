// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {HuffConfig, HuffNeoConfig, HuffNeoDeployer} from "foundry-huff-neo/HuffNeoDeployer.sol";

/// Deploys the forwarder and Disperse with CREATE2 through the deterministic deployer, so both have the
/// same address on every chain. A contract that is already deployed is skipped.
///
/// forge script script/Deploy.s.sol --rpc-url <RPC_URL> --private-key <KEY> --broadcast
contract Deploy is Script {
    using HuffNeoConfig for HuffConfig;

    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    /// The forwarder's address built into Disperse
    address constant FORWARDER = 0x6d93D11e4C74e195DEe61693650D4FabCB6D6013;
    bytes32 constant SALT = 0;

    function run() external returns (address forwarder, address disperse) {
        forwarder = deploy("src/Forwarder.huff");
        require(forwarder == FORWARDER, "the forwarder is not at the address built into Disperse");
        disperse = deploy("src/Disperse.huff");
    }

    function deploy(string memory file) internal returns (address addr) {
        bytes memory code = HuffNeoDeployer.config().creation_code(file);
        addr = vm.computeCreate2Address(SALT, keccak256(code), CREATE2_DEPLOYER);
        if (addr.code.length > 0) {
            console.log("%s already deployed at %s", file, addr);
            return addr;
        }

        vm.broadcast();
        (bool ok,) = CREATE2_DEPLOYER.call(abi.encodePacked(SALT, code));
        require(ok && addr.code.length > 0, "deployment failed");
        console.log("%s deployed at %s", file, addr);
    }
}
