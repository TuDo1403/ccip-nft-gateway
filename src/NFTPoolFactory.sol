// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {IERC721TokenPool} from "src/interfaces/IERC721TokenPool.sol";
import {IOwnable} from "src/interfaces/ext/IOwnable.sol";

import {CCIPCrossChainSenderReceiver} from "src/extensions/CCIPCrossChainSenderReceiver.sol";

contract NFTPoolFactory is CCIPCrossChainSenderReceiver {
    error InvalidTransferLimitPerRequest();
    error OnlyOtherChain(uint64 chainSelector);
    error NonExistentChain(uint64 chainSelector);
    error RemotePoolAlreadySet(uint64 chainSelector, address pool);

    uint256[50] private __gap;

    IERC20 internal s_linkToken;
    address internal s_erc721PoolBeacon;
    address internal s_erc1155PoolBeacon;
    mapping(uint64 remoteChainSelector => address factory) internal s_remoteFactories;

    function deployERC721TokenPool(
        address owner,
        bytes32 salt,
        address token,
        address rateLimitAdmin,
        address extStorage,
        uint32 transferLimitPerRequest,
        uint64 remoteChainSelector,
        address remotePool,
        bytes calldata extraArgs,
        bool dualDeployment
    ) external returns (IERC721TokenPool pool) {
        if (transferLimitPerRequest == 0) revert InvalidTransferLimitPerRequest();
        if (s_currentChainSelector == remoteChainSelector) revert OnlyOtherChain(remoteChainSelector);
        if (s_remoteFactories[remoteChainSelector] == address(0)) revert NonExistentChain(remoteChainSelector);
        if (dualDeployment && remotePool != address(0)) revert RemotePoolAlreadySet(remoteChainSelector, remotePool);

        if (dualDeployment) {}

        // Ensure a unique deployment between senders even if the same input parameter is used to prevent
        // DOS/front running attacks
        salt = keccak256(abi.encodePacked(salt, msg.sender, owner));
        pool = IERC721TokenPool(Clones.cloneDeterministic(s_erc721PoolBeacon, salt));

        // Initialize the pool
        pool.initialize(address(this), address(s_router), token, s_currentChainSelector);
        if (extStorage != address(0)) pool.setExternalStorage(extStorage);
        if (rateLimitAdmin != address(0)) pool.setRateLimitAdmin(rateLimitAdmin);
        if (remotePool != address(0)) pool.addRemotePool(remoteChainSelector, remotePool, extraArgs);

        pool.setTransferLimitPerRequest(s_currentChainSelector, transferLimitPerRequest);

        IOwnable(address(pool)).transferOwnership(msg.sender);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal virtual override {}
}
