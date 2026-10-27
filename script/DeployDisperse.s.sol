// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import {Create2Deploy} from "./Create2Deploy.sol";

/// Deploys Disperse. Disperse pays contracts through the forwarder, so deploy the forwarder first.
///
/// forge script script/DeployDisperse.s.sol --rpc-url <RPC_URL> --private-key <KEY> --broadcast
contract DeployDisperse is Create2Deploy {
    function run() external returns (address disperse) {
        require(FORWARDER.code.length > 0, "deploy the forwarder first, with DeployForwarder.s.sol");
        disperse = deploy("src/Disperse.huff", DISPERSE_SALT);
        require(disperse == DISPERSE, "Disperse is not at the expected address");
    }
}
