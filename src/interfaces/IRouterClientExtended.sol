// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

interface IRouterClientExtended is IRouterClient {
    function getArmProxy() external view returns (address);
}
