// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface ITokenPoolCallback is IAccessControl {
    function initialize(address admin, uint32 fixedGas, uint32 dynamicGas, address router, uint64 currentChainSelector)
        external;

    function isSupportedToken(address token) external view returns (bool);

    function addRemotePool(uint64 remoteChainSelector, address remotePool) external;

    function mapRemoteToken(address localToken, uint64 remoteChainSelector, address remoteToken) external;

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function TOKEN_POOL_OWNER_ROLE() external view returns (bytes32);

    function PAUSER_ROLE() external view returns (bytes32);

    function RATE_LIMITER_ROLE() external pure returns (bytes32);

    function SHARED_STORAGE_SETTER_ROLE() external pure returns (bytes32);
}
