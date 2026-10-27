// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import {Create2Deploy} from "./Create2Deploy.sol";

/// Deploys the forwarder at the address built into Disperse.
///
/// forge script script/DeployForwarder.s.sol --rpc-url <RPC_URL> --private-key <KEY> --broadcast
contract DeployForwarder is Create2Deploy {
    function run() external returns (address forwarder) {
        forwarder = deploy("src/Forwarder.huff", FORWARDER_SALT);
        require(forwarder == FORWARDER, "the forwarder is not at the address built into Disperse");
    }
}
