// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MockRouter} from "test/mocks/MockRouter.sol";
import {MockTokenAdminRegistry} from "test/mocks/MockTokenAdminRegistry.sol";

contract CCIPLocalSimulator {
    MockRouter public router= new MockRouter();
    MockTokenAdminRegistry public tokenAdminRegistry = new MockTokenAdminRegistry();
    address public rmnProxy = router.getArmProxy();

    constructor() {
        router = new MockRouter();
        router.setFee(10 ether);
    }

    function switchChain(uint64 chainSelector) external {
        router.switchChain(chainSelector);
    }

    function supportChain(uint256 chainSelector) external {
        router.supportChain(chainSelector);
    }
}
