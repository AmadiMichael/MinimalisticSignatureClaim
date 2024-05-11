// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MinimalisticSignatureClaim} from "../src/SolidityMSC.sol";
import {BaseMSCTest} from "./BaseMSC.t.sol";

contract SolidityMSCTest is BaseMSCTest {
    function _deployAndReturnMSC() internal override returns (address) {
        return address(new MinimalisticSignatureClaim(address(token), owner, START, DEADLINE));
    }
}
