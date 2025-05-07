// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

library Pool {
    struct LockOrBurn {
        uint64 remoteChainSelector;
        address originalSender;
        uint256 amount;
        address localToken;
        bytes extraData;
    }

    struct ReleaseOrMint {
        Any2EVMAddress originalSender;
        uint64 remoteChainSelector;
        Any2EVMAddress receiver;
        uint256 amount;
        Any2EVMAddress localToken;
        Any2EVMAddress remotePoolAddress;
        bytes remotePoolData;
    }
}
