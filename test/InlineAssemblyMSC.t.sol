// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MinimalisticSignatureClaim} from "../src/InlineAssemblyMSC.sol";
import {BaseMSCTest} from "./BaseMSC.t.sol";

contract InlineAssemblyMSCTest is BaseMSCTest {
    function _deployAndReturnMSC() internal override returns (address) {
        return address(new MinimalisticSignatureClaim(address(token), owner, START, DEADLINE));
    }
}
