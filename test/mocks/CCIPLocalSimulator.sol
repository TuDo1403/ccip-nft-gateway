// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MockRouter} from "test/mocks/MockRouter.sol";
import {MockTokenAdminRegistry} from "test/mocks/MockTokenAdminRegistry.sol";

contract CCIPLocalSimulator {
    uint64 public currentChainSelector = 16015286601757825753;
    uint64 public remoteChainSelector = ~currentChainSelector;

    MockRouter public router = new MockRouter();
    MockTokenAdminRegistry public tokenAdminRegistry = new MockTokenAdminRegistry();
    address public rmnProxy = router.getArmProxy();

    constructor() {
        router.setFee(10 ether);
    }
}
