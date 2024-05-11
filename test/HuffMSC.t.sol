// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseMSCTest} from "./BaseMSC.t.sol";
import {HuffDeployer} from "./../lib/foundry-huff/src/HuffDeployer.sol";

contract HuffMSCTest is BaseMSCTest {
    function _deployAndReturnMSC() internal override returns (address) {
        return HuffDeployer.config().with_code(
            string.concat(
                "#define constant TOKEN_ADDRESS = ",
                vm.toString(address(token)),
                "\n #define constant OWNER = ",
                vm.toString(owner),
                "\n #define constant START =",
                vm.toString(bytes32(START)),
                "\n #define constant DEADLINE = ",
                vm.toString(bytes32(DEADLINE)),
                "\n"
            )
        ).with_evm_version("paris").deploy("HuffMSC");
    }
}
