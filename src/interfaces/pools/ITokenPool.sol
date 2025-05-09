// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ITypeAndVersion} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/ITypeAndVersion.sol";

interface ITokenPool is ITypeAndVersion {
    event GasLimitConfigured(address indexed by, uint32 fixedGas, uint32 dynamicGas);
    event RemotePoolAdded(address indexed by, uint64 indexed remoteChainSelector, address indexed remotePool);
    event RemotePoolRemoved(address indexed by, uint64 indexed remoteChainSelector);
    event RemoteTokenMapped(
        address indexed by, uint64 indexed remoteChainSelector, address indexed localToken, address remoteToken
    );
    event RemoteTokenUnmapped(address indexed by, uint64 indexed remoteChainSelector, address indexed localToken);

    function TOKEN_POOL_OWNER_ROLE() external view returns (bytes32);

    function addRemotePool(uint64 remoteChainSelector, address remotePool) external;

    function removeRemotePool(uint64 remoteChainSelector) external;

    function mapRemoteToken(address localToken, uint64 remoteChainSelector, address remoteToken) external;

    function unmapRemoteToken(address localToken, uint64 remoteChainSelector) external;

    function setGasLimitConfig(uint32 fixedGas, uint32 dynamicGas) external;

    function getRemotePools()
        external
        view
        returns (uint64[] memory remoteChainSelectors, address[] memory remotePools);

    function getRemotePool(uint64 remoteChainSelector) external view returns (address remotePool);

    function isSupportedToken(address token) external view returns (bool yes);

    function getGasLimitConfig() external view returns (uint32 fixedGas, uint32 dynamicGas);
}
