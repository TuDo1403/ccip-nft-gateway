// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ICCIPSenderReceiver} from "src/interfaces/extensions/ICCIPSenderReceiver.sol";
import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

interface ITokenPoolAbstract {
    event GasLimitConfigured(address indexed by, uint32 fixedGas, uint32 dynamicGas);
    event RemotePoolRemoved(address indexed by, uint64 indexed remoteChainSelector);

    function TOKEN_POOL_OWNER_ROLE() external view returns (bytes32);

    function setGasLimitConfig(uint32 fixedGas, uint32 dynamicGas) external;

    function removeRemotePool(uint64 remoteChainSelector) external;

    function getRemotePools() external view returns (ICCIPSenderReceiver.RemoteChainConfig[] memory pools);

    function getRemotePool(uint64 remoteChainSelector) external view returns (Any2EVMAddress memory remotePool);

    function isSupportedToken(address token) external view returns (bool yes);

    function getGasLimitConfig() external view returns (uint32 fixedGas, uint32 dynamicGas);
}
