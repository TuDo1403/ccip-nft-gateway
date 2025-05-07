// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Pool {
    struct LockOrBurn {
        uint64 remoteChainSelector;
        address localToken;
        bytes extraData;
    }

    struct ReleaseOrMint {
        address originalSender;
        uint64 remoteChainSelector;
        address receiver;
        address localToken;
        address remotePoolAddress;
        bytes remotePoolData;
    }
}
