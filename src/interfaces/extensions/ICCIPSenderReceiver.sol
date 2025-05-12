// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRMN} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRMN.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IRouterClientExtended} from "src/interfaces/external/IRouterClientExtended.sol";

interface ICCIPSenderReceiver is IAny2EVMMessageReceiver, IERC165 {
    /// @dev Revert if the remote chain is cursed by RMN.
    error CursedByRMN();
    /// @dev Revert if the sender is not enabled for the remote chain.
    error SenderNotEnabled(uint64 chainSelector, address sender);
    /// @dev Revert if the provided chain selector is current chain selector.
    error OnlyRemoteChain(uint64 chainSelector);
    /// @dev Revert if the provided chain selector is not current chain selector.
    error OnlyLocalChain(uint64 chainSelector);
    /// @dev Revert if the provided address is zero.
    error ZeroAddressNotAllowed();
    /// @dev Revert if the provided value is zero.
    error ZeroValueNotAllowed();
    /// @dev Revert if the provided address is not a valid router.
    error InvalidRouter(address expected, address actual);
    /// @dev Revert if the provided `chainSelector` is not enabled.
    error NonExistentChain(uint64 chainSelector);
    /// @dev Revert if the provided `chainSelector` is already enabled.
    error ChainAlreadyEnabled(uint64 chainSelector);
    /// @dev Revert if the provided `chainSelector` is not supported by CCIP router.
    error ChainNotSupported(uint64 chainSelector);
    /// @dev Revert if not allow receiving msg.value.
    error MsgValueNotAllowed(uint256 value);
    /// @dev Revert if failed to refund to the sender.
    error RefundFailed(address to, uint256 value);
    /// @dev Revert if provided fee is insufficient.
    error InsufficientAllowance(uint256 expected, uint256 actual);

    /// @dev Emit when refunded to the sender.
    event Refunded(address indexed to, uint256 value);
    /// @dev Emit when the message is sent to CCIP.
    event MessageSent(address indexed by, bytes32 indexed messageId);
    /// @dev Emit when the message is received from CCIP.
    event MessageReceived(address by, bytes32 indexed messageId);
    /// @dev Emit when the given `chainSelector` is disabled.
    event RemoteChainDisabled(address indexed by, uint64 indexed chainSelector);
    /// @dev Emit when the given `chainSelector` is enabled.
    event RemoteChainEnabled(address indexed by, uint64 indexed chainSelector, address indexed remoteSender);

    /*
     * @dev Check whether the given `feeToken` is supported for the given `remoteChainSelector`.
     */
    function isFeeTokenSupported(uint64 remoteChainSelector, address feeToken) external view returns (bool yes);

    /*
     * @dev Get all supported fee tokens for the given `remoteChainSelector`.
     */
    function getFeeTokens(uint64 remoteChainSelector) external view returns (address[] memory feeTokens);

    /*
     * @dev Check whether given `chainSelector` is current chain selector.
     */
    function isLocalChain(uint64 currentChainSelector) external view returns (bool yes);

    /*
     * @dev Check whether given `chainSelector` is supported by this contract.
     */
    function isSupportedChain(uint64 remoteChainSelector) external view returns (bool yes);

    /*
     * @dev Get all supported chains for this contract.
     */
    function getSupportedChains() external view returns (uint64[] memory remoteChainSelectors);

    /*
     * @dev Check whether the given `sender` is enabled for the given `remoteChainSelector`.
     */
    function isSenderEnabled(uint64 remoteChainSelector, address sender) external view returns (bool yes);

    /*
     * @dev Get chain selector of the current chain.
     */
    function getCurrentChainSelector() external view returns (uint64 currentChainSelector);

    /*
     * @dev Get CCIP router address.
     */
    function getRouter() external view returns (IRouterClientExtended router);

    /*
     * @dev Get RMN proxy address.
     */
    function getRmnProxy() external view returns (IRMN rmnProxy);
}
