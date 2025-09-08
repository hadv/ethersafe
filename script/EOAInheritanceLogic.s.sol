// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {EOAInheritanceLogic} from "../src/EOAInheritanceLogic.sol";

contract EOAInheritanceLogicScript is Script {
    EOAInheritanceLogic public inheritanceLogic;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        inheritanceLogic = new EOAInheritanceLogic();

        console.log("EOAInheritanceLogic deployed at:", address(inheritanceLogic));

        vm.stopBroadcast();
    }
}
