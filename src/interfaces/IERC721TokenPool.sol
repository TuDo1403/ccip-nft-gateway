// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

interface IERC721TokenPool is IAny2EVMMessageReceiver {
    error ChainNotEnabled(uint64 chainSelector);
    error InvalidNFT(address expected, address actual);
    error NFTLockFailed(address from, address to, uint256 tokenId, uint256 quantity);
    error NFTReleaseFailed(address from, address to, uint256 tokenId, uint256 quantity);
    error OnlyOtherChain(uint64 chainSelector);
    error SenderNotEnabled(uint64 chainSelector, address sender);
    error RefundFailed(address to, uint256 amount);
    error InsufficientBalance(PayFeesIn feeKind, uint256 currentBalance, uint256 requiredBalance);

    enum PayFeesIn {
        Native,
        LINK
    }

    event Refunded(address indexed to, uint256 amount);
    event ChainDisabled(uint64 indexed chainSelector);
    event ChainEnabled(uint64 indexed chainSelector, address indexed pool, bytes extraArgs);
    event RateLimitAdminSet(address indexed by, address rateLimitAdmin);

    event CrossChainReceived(
        address indexed from, address indexed to, uint256[] ids, uint64 srcChainSelector, uint64 dstChainSelector
    );
    event CrossChainSent(
        address indexed from, address indexed to, uint256[] ids, uint64 srcChainSelector, uint64 dstChainSelector
    );

    function initialize(address owned, address router, address token, uint64 currentChainSelector) external;

    function addRemotePool(uint64 remoteChainSelector, address pool, bytes calldata extraArgs) external;

    function setRateLimitAdmin(address rateLimitAdmin) external;

    function setExternalStorage(address extStorage) external;

    function setTransferLimitPerRequest(uint64 chainSelector, uint32 limit) external;

    // function crossChainTransfer(
    //     address to,
    //     uint256 tokenId,
    //     uint256 quantity,
    //     uint64 dstChainSelector,
    //     PayFeesIn payFeesIn
    // ) external payable returns (bytes32 messageId);
    // function enableChain(uint64 srcChainSelector, address pool, bytes calldata extraArgs) external;
    // function disableChain(uint64 srcChainSelector) external;
    // function getCCIPRouter() external view returns (address);
    // function getCurrentChainSelector() external view returns (uint64);
    // function getNFTAddress() external view returns (address);
    // function getRoninGateway() external view returns (address);
    // function getLinkToken() external view returns (address);
    // function getSourcePool(uint64 srcChainSelector) external view returns (address, bytes memory);
}
