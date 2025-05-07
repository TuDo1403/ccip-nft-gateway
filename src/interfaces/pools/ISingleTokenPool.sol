// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

interface ISingleTokenPool {
    error OnlyLocalToken(address expected, address actual);

    event RemotePoolAdded(
        address indexed by, uint64 indexed remoteChainSelector, Any2EVMAddress remotePool, Any2EVMAddress token
    );

    function addRemotePool(
        uint64 remoteChainSelector,
        Any2EVMAddress calldata remotePool,
        Any2EVMAddress calldata remoteToken
    ) external;

    function getToken() external view returns (address token);

    function getRemoteToken(uint64 remoteChainSelector) external view returns (Any2EVMAddress memory remoteToken);
}
