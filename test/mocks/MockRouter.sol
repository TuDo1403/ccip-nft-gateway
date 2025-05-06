// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MockCCIPRouter} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockRouter.sol";
import {IRouterClientExtended} from "src/interfaces/external/IRouterClientExtended.sol";
import {MockRmnProxy} from "test/mocks/MockRmnProxy.sol";
import {MockEVM2EVMOnRamp} from "test/mocks/MockEVM2EVMOnRamp.sol";
import {WETH} from "@solady/tokens/WETH.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {MockPriceRegistry} from "test/mocks/MockPriceRegistry.sol";

contract MockRouter is MockCCIPRouter, IRouterClientExtended {
    address internal immutable i_armProxy = address(new MockRmnProxy());
    address internal immutable i_weth = address(new WETH());
    address internal immutable i_link = address(new MockERC20());
    Vm internal immutable vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    constructor() {
        MockERC20(i_link).initialize("LINK", "LINK", 18);
        deployOnRamp();
    }

    function deployOnRamp() public {
        address where = address(1234567890);
        bytes memory creationCode = type(MockEVM2EVMOnRamp).creationCode;
        vm.etch(where, abi.encodePacked(creationCode, ""));
        (bool success, bytes memory runtimeBytecode) = where.call{value: 0}("");
        require(success, "StdCheats deployCodeTo(string,bytes,uint256,address): Failed to create runtime bytecode.");
        vm.etch(where, runtimeBytecode);

        address[] memory feeTokens = new address[](2);
        feeTokens[0] = i_weth;
        feeTokens[1] = i_link;

        MockEVM2EVMOnRamp onRamp = MockEVM2EVMOnRamp(where);
        MockPriceRegistry(onRamp.getPriceRegistry()).setFeeTokens(feeTokens);
    }

    function getArmProxy() external view returns (address) {
        return i_armProxy;
    }

    function getWrappedNative() external view returns (address) {
        return i_weth;
    }
}
