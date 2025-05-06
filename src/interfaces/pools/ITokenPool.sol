// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ITokenPoolCallback} from "src/interfaces/pools/ITokenPoolCallback.sol";

interface ITokenPool is ITokenPoolCallback {
    error OnlyLocalToken(address expected, address actual);

    struct LockOrBurn {
        bytes receiver;
        uint64 remoteChainSelector;
        address originalSender;
        uint256 amount;
        address localToken;
        bytes extraData;
    }

    struct ReleaseOrMint {
        bytes originalSender;
        uint64 remoteChainSelector;
        address receiver;
        uint256 amount;
        address localToken;
        bytes remotePoolAddress;
        bytes remotePoolData;
    }

    event GasLimitConfigured(address indexed by, uint32 fixedGas, uint32 dynamicGas);
    event RemotePoolAdded(
        address indexed by, uint64 indexed remoteChainSelector, address indexed remotePool, address token
    );
    event RemotePoolRemoved(address indexed by, uint64 indexed remoteChainSelector);
}
