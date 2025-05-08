// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRMN} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRMN.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IRouterClientExtended} from "src/interfaces/external/IRouterClientExtended.sol";

interface ICCIPSenderReceiver is IAny2EVMMessageReceiver, IERC165 {
    error CursedByRMN();
    error SenderNotEnabled(uint64 chainSelector, address sender);
    error OnlyRemoteChain(uint64 chainSelector);
    error OnlyLocalChain(uint64 chainSelector);
    error ZeroAddressNotAllowed();
    error ZeroValueNotAllowed();
    error InvalidRouter(address expected, address actual);
    error NonExistentChain(uint64 chainSelector);
    error ChainAlreadyEnabled(uint64 chainSelector);
    error ChainNotSupported(uint64 chainSelector);
    error MsgValueNotAllowed(uint256 value);
    error RefundFailed(address to, uint256 value);
    error InsufficientAllowance(uint256 expected, uint256 actual);

    event Refunded(address indexed to, uint256 value);
    event MessageSent(address indexed by, bytes32 indexed messageId);
    event MessageReceived(address by, bytes32 indexed messageId);
    event RemoteChainDisabled(address indexed by, uint64 indexed chainSelector);
    event RemoteChainEnabled(address indexed by, uint64 indexed chainSelector, address indexed remoteSender);

    function isFeeTokenSupported(uint64 remoteChainSelector, address feeToken) external view returns (bool yes);

    function getFeeTokens(uint64 remoteChainSelector) external view returns (address[] memory feeTokens);

    function isLocalChain(uint64 currentChainSelector) external view returns (bool yes);

    function isSupportedChain(uint64 remoteChainSelector) external view returns (bool yes);

    function getSupportedChains() external view returns (uint64[] memory remoteChainSelectors);

    function isSenderEnabled(uint64 remoteChainSelector, address sender) external view returns (bool yes);

    function getCurrentChainSelector() external view returns (uint64 currentChainSelector);

    function getRouter() external view returns (IRouterClientExtended router);

    function getRmnProxy() external view returns (IRMN rmnProxy);
}
