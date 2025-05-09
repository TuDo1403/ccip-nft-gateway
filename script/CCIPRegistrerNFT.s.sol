// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {MockERC721Mintable} from "test/mocks/MockERC721Mintable.sol";

contract CCIPRegisterNFT is Script {
    uint256 internal saigonFork;
    uint256 internal sepoliaFork;

    function setUp() external {
        saigonFork = vm.createSelectFork("ronin-testnet");
        sepoliaFork = vm.createSelectFork("sepolia");
    }

    function run() external {}
}
