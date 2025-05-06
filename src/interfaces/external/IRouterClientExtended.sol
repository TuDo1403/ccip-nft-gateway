// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IRouter} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouter.sol";

interface IRouterClientExtended is IRouter, IRouterClient {
    function getArmProxy() external view returns (address);
    function getWrappedNative() external view returns (address);
}
