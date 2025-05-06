// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IEVM2EVMOnRamp} from "src/interfaces/external/IEVM2EVMOnRamp.sol";
import {MockPriceRegistry} from "test/mocks/MockPriceRegistry.sol";

contract MockEVM2EVMOnRamp is IEVM2EVMOnRamp {
    address internal immutable i_priceRegistry = address(new MockPriceRegistry());

    function getDynamicConfig() external view override returns (DynamicConfig memory dynamicConfig) {
        dynamicConfig.priceRegistry = i_priceRegistry;
    }

    function getPriceRegistry() external view returns (address) {
        return i_priceRegistry;
    }
}
