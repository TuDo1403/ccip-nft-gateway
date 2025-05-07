// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface ITokenPoolCallback is IAccessControl {
    function initialize(
        address admin,
        address token,
        uint32 fixedGas,
        uint32 dynamicGas,
        address router,
        uint64 currentChainSelector
    ) external;

    function addRemotePool(
        uint64 remoteChainSelector,
        Any2EVMAddress calldata remotePool,
        Any2EVMAddress calldata remoteToken
    ) external;

    function getToken() external view returns (address);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function TOKEN_POOL_OWNER_ROLE() external view returns (bytes32);

    function PAUSER_ROLE() external view returns (bytes32);

    function RATE_LIMITER_ROLE() external pure returns (bytes32);
}
