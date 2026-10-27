// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

import {DeployDisperse} from "../script/DeployDisperse.s.sol";
import {DeployForwarder} from "../script/DeployForwarder.s.sol";
import {Test} from "forge-std/Test.sol";

/// Runs both deploy scripts in order, so their salts land on the expected addresses.
contract DeployTest is Test {
    function test_deploysTheForwarderThenDisperse() public {
        address forwarder = new DeployForwarder().run();
        address disperse = new DeployDisperse().run();
        assertGt(forwarder.code.length, 0);
        assertGt(disperse.code.length, 0);
    }

    function test_disperseNeedsTheForwarder() public {
        DeployDisperse script = new DeployDisperse();
        vm.expectRevert("deploy the forwarder first, with DeployForwarder.s.sol");
        script.run();
    }
}
