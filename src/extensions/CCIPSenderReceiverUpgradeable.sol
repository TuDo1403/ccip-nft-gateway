// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRMN} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRMN.sol";
import {IWrappedNative} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IWrappedNative.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IRouterClientExtended} from "src/interfaces/external/IRouterClientExtended.sol";
import {IEVM2EVMOnRamp} from "src/interfaces/external/IEVM2EVMOnRamp.sol";
import {ICCIPSenderReceiver} from "src/interfaces/extensions/ICCIPSenderReceiver.sol";

abstract contract CCIPSenderReceiverUpgradeable is Initializable, ICCIPSenderReceiver {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @dev Gap for future storage
    uint256[50] private __gap1;

    /// @dev Current chain selector
    uint64 private s_currentChainSelector;
    /// @dev CCIP Risk Management Network Proxy
    IRMN private s_rmnProxy;
    /// @dev CCIP Router
    IRouterClientExtended private s_router;
    /// @dev Remote chain selectors set
    EnumerableSet.UintSet private s_remoteChainSelectors;
    /// @dev Mapping of remote chain selector to enabled sender. This is the address that is allowed to send messages from the remote chain.
    mapping(uint64 remoteChainSelector => address) private s_remoteSenders;

    /// @dev Gap for future storage
    uint256[50] private __gap2;

    modifier onlyEnabledChain(uint64 remoteChainSelector) {
        _requireEnabledChain(remoteChainSelector);
        _;
    }

    modifier onlyLocalChain(uint64 currentChainSelector) {
        _requireLocalChain(currentChainSelector);
        _;
    }

    modifier nonZero(address addr) {
        _requireNonZero(addr);
        _;
    }

    modifier notCursed(uint64 remoteChainSelector) {
        _requireNotCursed(remoteChainSelector);
        _;
    }

    function __CCIPSenderReceiver_init(address router, uint64 currentChainSelector) internal onlyInitializing {
        __CCIPSenderReceiver_init_unchained(router, currentChainSelector);
    }

    function __CCIPSenderReceiver_init_unchained(address router, uint64 currentChainSelector)
        internal
        onlyInitializing
    {
        _requireNonZero(currentChainSelector);

        s_router = IRouterClientExtended(router);
        s_rmnProxy = IRMN(s_router.getArmProxy());
        s_currentChainSelector = currentChainSelector;
    }

    /**
     * @inheritdoc IAny2EVMMessageReceiver
     */
    function ccipReceive(Client.Any2EVMMessage calldata message)
        external
        override
        notCursed(message.sourceChainSelector)
    {
        address sender = abi.decode(message.sender, (address));

        _requireEnabledSender(message.sourceChainSelector, sender);
        _requireRouter();

        _ccipReceive(message);

        emit MessageReceived(sender, message.messageId);
    }

    /**
     * @inheritdoc ICCIPSenderReceiver
     */
    function isFeeTokenSupported(uint64 remoteChainSelector, address feeToken) external view returns (bool yes) {
        address[] memory feeTokens = getFeeTokens(remoteChainSelector);
        uint256 feeTokenCount = feeTokens.length;
        if (feeTokenCount == 0) return false;

        for (uint256 i; i < feeTokenCount; ++i) {
            if (feeTokens[i] == feeToken) return true;
        }

        return false;
    }

    /**
     * @inheritdoc ICCIPSenderReceiver
     */
    function getFeeTokens(uint64 remoteChainSelector)
        public
        view
        onlyEnabledChain(remoteChainSelector)
        returns (address[] memory feeTokens)
    {
        return IEVM2EVMOnRamp(s_router.getOnRamp(remoteChainSelector)).getDynamicConfig().priceRegistry.getFeeTokens();
    }

    /**
     * @inheritdoc ICCIPSenderReceiver
     */
    function isLocalChain(uint64 currentChainSelector) public view returns (bool yes) {
        return currentChainSelector == s_currentChainSelector;
    }

    /**
     * @inheritdoc ICCIPSenderReceiver
     */
    function isSupportedChain(uint64 remoteChainSelector) public view returns (bool yes) {
        return s_remoteChainSelectors.contains(remoteChainSelector);
    }

    /**
     * @inheritdoc ICCIPSenderReceiver
     */
    function isSenderEnabled(uint64 remoteChainSelector, address sender) public view returns (bool yes) {
        if (!isSupportedChain(remoteChainSelector)) return false;
        return s_remoteSenders[remoteChainSelector] == sender;
    }

    /**
     * @inheritdoc ICCIPSenderReceiver
     */
    function getSupportedChains() public view returns (uint64[] memory remoteChainSelectors) {
        uint256[] memory values = s_remoteChainSelectors.values();
        assembly ("memory-safe") {
            remoteChainSelectors := values
        }
    }

    /**
     * @inheritdoc ICCIPSenderReceiver
     */
    function getCurrentChainSelector() public view returns (uint64 currentChainSelector) {
        return s_currentChainSelector;
    }

    /**
     * @inheritdoc ICCIPSenderReceiver
     */
    function getRouter() public view returns (IRouterClientExtended router) {
        return s_router;
    }

    /**
     * @inheritdoc ICCIPSenderReceiver
     */
    function getRmnProxy() external view returns (IRMN rmnProxy) {
        return s_rmnProxy;
    }

    /**
     * @notice IERC165 supports an interfaceId
     * @param interfaceId The interfaceId to check
     * @return true if the interfaceId is supported
     * @dev Should indicate whether the contract implements IAny2EVMMessageReceiver
     * e.g. return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IERC165).interfaceId
     * This allows CCIP to check if ccipReceive is available before calling it.
     * If this returns false or reverts, only tokens are transferred to the receiver.
     * If this returns true, tokens are transferred and ccipReceive is called atomically.
     * Additionally, if the receiver address does not have code associated with
     * it at the time of execution (EXTCODESIZE returns 0), only tokens will be transferred.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ICCIPSenderReceiver).interfaceId
            || interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice Override this function in your implementation.
     * @param message Any2EVMMessage
     */
    function _ccipReceive(Client.Any2EVMMessage calldata message) internal virtual;

    /**
     * @dev Enable a remote chain
     * @param remoteChainSelector The chain selector of the remote chain
     * @param remoteSender The address of the sender on the remote chain
     */
    function _addRemoteChain(uint64 remoteChainSelector, address remoteSender) internal {
        _requireNonZero(remoteSender);

        if (remoteChainSelector == s_currentChainSelector) revert OnlyRemoteChain(remoteChainSelector);
        if (!s_router.isChainSupported(remoteChainSelector)) revert ChainNotSupported(remoteChainSelector);

        if (!s_remoteChainSelectors.add(remoteChainSelector)) revert ChainAlreadyEnabled(remoteChainSelector);
        s_remoteSenders[remoteChainSelector] = remoteSender;

        emit RemoteChainEnabled(msg.sender, remoteChainSelector, remoteSender);
    }

    /**
     * @dev Disable a remote chain
     * @param remoteChainSelector The chain selector of the remote chain
     */
    function _removeRemoteChain(uint64 remoteChainSelector) internal {
        if (!s_remoteChainSelectors.remove(remoteChainSelector)) revert NonExistentChain(remoteChainSelector);
        delete s_remoteSenders[remoteChainSelector];

        emit RemoteChainDisabled(msg.sender, remoteChainSelector);
    }

    /**
     * @notice Send data to a remote chain and pay fee by ERC20 token
     * If the feeToken is address(0), the fee will be wrapped into WrappedNative token.
     * Revert if the feeToken is not supported by the remote chain.
     */
    function _sendDataPayFeeToken(
        uint64 remoteChainSelector,
        address receiver,
        bytes memory data,
        uint256 gasLimit,
        bool allowOutOfOrderExecution,
        address feeToken
    ) internal notCursed(remoteChainSelector) returns (bytes32 messageId) {
        _requireNonZero(receiver);
        _requireNonZero(gasLimit);
        _requireNonZero(data.length);

        (uint256 fee, Client.EVM2AnyMessage memory message) =
            _getSendDataFee(remoteChainSelector, receiver, data, gasLimit, allowOutOfOrderExecution, feeToken);

        if (feeToken == address(0)) {
            if (msg.value < fee) revert InsufficientAllowance(fee, msg.value);

            feeToken = s_router.getWrappedNative();
            // Overwrite feeToken to wrapped native token
            message.feeToken = feeToken;
            IWrappedNative(feeToken).deposit{value: fee}();

            uint256 overspent = msg.value - fee;
            if (overspent > 0) {
                // solhint-disable-next-line avoid-low-level-calls
                (bool success,) = msg.sender.call{value: overspent}("");
                if (!success) revert RefundFailed(msg.sender, overspent);
                emit Refunded(msg.sender, overspent);
            }
        } else {
            if (msg.value != 0) revert MsgValueNotAllowed(msg.value);
            IERC20(feeToken).safeTransferFrom(msg.sender, address(this), fee);
        }

        IERC20(feeToken).approve(address(s_router), fee);

        messageId = s_router.ccipSend(remoteChainSelector, message);

        emit MessageSent(msg.sender, messageId);
    }

    /**
     * @notice Estimate the fee for sending data to a remote chain
     */
    function _getSendDataFee(
        uint64 remoteChainSelector,
        address receiver,
        bytes memory data,
        uint256 gasLimit,
        bool allowOutOfOrderExecution,
        address feeToken
    ) internal view onlyEnabledChain(remoteChainSelector) returns (uint256 fee, Client.EVM2AnyMessage memory message) {
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: gasLimit, allowOutOfOrderExecution: allowOutOfOrderExecution})
            ),
            feeToken: feeToken
        });

        fee = s_router.getFee(remoteChainSelector, message);
    }

    function _getRemoteSender(uint64 remoteChainSelector) internal view returns (address remoteAddress) {
        return s_remoteSenders[remoteChainSelector];
    }

    function _requireLocalChain(uint64 currentChainSelector) internal view {
        if (currentChainSelector != s_currentChainSelector) revert OnlyLocalChain(currentChainSelector);
    }

    function _requireRouter() internal view {
        if (msg.sender != address(s_router)) revert InvalidRouter(address(s_router), msg.sender);
    }

    function _requireNonZero(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddressNotAllowed();
    }

    function _requireNonZero(uint256 val) internal pure {
        if (val == 0) revert ZeroValueNotAllowed();
    }

    function _requireNotCursed(uint64 remoteChainSelector) internal view {
        if (s_rmnProxy.isCursed(bytes16(uint128(remoteChainSelector)))) revert CursedByRMN();
    }

    function _requireEnabledChain(uint64 remoteChainSelector) internal view {
        if (!isSupportedChain(remoteChainSelector)) revert NonExistentChain(remoteChainSelector);
    }

    function _requireEnabledSender(uint64 remoteChainSelector, address sender) internal view {
        if (!isSenderEnabled(remoteChainSelector, sender)) revert SenderNotEnabled(remoteChainSelector, sender);
    }
}
