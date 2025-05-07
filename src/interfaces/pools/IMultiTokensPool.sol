// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

interface IMultiTokensPool {
    error OnlyLocalToken();
    error LengthMismatch(uint256 expected, uint256 actual);

    event RemotePoolAdded(
        address indexed by,
        uint64 indexed remoteChainSelector,
        Any2EVMAddress remotePool,
        Any2EVMAddress[] remoteTokens,
        address[] localTokens
    );
}
