// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRMN} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRMN.sol";
import {IWrappedNative} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IWrappedNative.sol";
import {IPriceRegistry} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IPriceRegistry.sol";
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
import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

abstract contract CCIPSenderReceiverUpgradeable is Initializable, ICCIPSenderReceiver {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256[50] private __gap1;

    uint64 internal s_currentChainSelector;
    IRMN internal s_rmnProxy;
    IRouterClientExtended internal s_router;
    EnumerableSet.UintSet internal s_remoteChainSelectors;
    mapping(uint64 remoteChainSelector => RemoteChainConfig remoteChainConfig) internal s_remoteChainConfigs;

    uint256[50] private __gap2;

    modifier onlyEnabledSender(uint64 remoteChainSelector, Any2EVMAddress memory sender) {
        _requireEnabledSender(remoteChainSelector, sender);
        _;
    }

    modifier onlyEnabledChain(uint64 remoteChainSelector) {
        _requireEnabledChain(remoteChainSelector);
        _;
    }

    modifier onlyRemoteChain(uint64 remoteChainSelector) {
        _requireRemoteChain(remoteChainSelector);
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

    modifier onlyRouter() {
        _requireRouter();
        _;
    }

    modifier notCursed(uint64 remoteChainSelector) {
        _requireNotCursed(remoteChainSelector);
        _;
    }

    function __CCIPSenderReceiverUpgradeable_init(address router, uint64 currentChainSelector)
        internal
        onlyInitializing
    {
        __CCIPSenderReceiverUpgradeable_init_unchained(router, currentChainSelector);
    }

    function __CCIPSenderReceiverUpgradeable_init_unchained(address router, uint64 currentChainSelector)
        internal
        nonZero(router)
        onlyInitializing
    {
        _requireNonZero(currentChainSelector);

        s_router = IRouterClientExtended(router);
        s_rmnProxy = IRMN(s_router.getArmProxy());
        s_currentChainSelector = currentChainSelector;
    }

    /// @inheritdoc IAny2EVMMessageReceiver
    function ccipReceive(Client.Any2EVMMessage calldata message)
        external
        override
        onlyRouter
        notCursed(message.sourceChainSelector)
        onlyEnabledChain(message.sourceChainSelector)
        onlyEnabledSender(message.sourceChainSelector, Any2EVMAddress(message.sender))
    {
        _ccipReceive(message);

        emit MessageReceived(Any2EVMAddress(message.sender), message.messageId);
    }

    function isFeeTokenSupported(uint64 remoteChainSelector, address token) external view returns (bool) {
        address[] memory feeTokens = getFeeTokens(remoteChainSelector);
        uint256 feeTokenCount = feeTokens.length;
        if (feeTokenCount == 0) return false;

        for (uint256 i; i < feeTokenCount; ++i) {
            if (feeTokens[i] == token) return true;
        }

        return false;
    }

    function getFeeTokens(uint64 remoteChainSelector)
        public
        view
        onlyRemoteChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
        returns (address[] memory feeTokens)
    {
        return IPriceRegistry(IEVM2EVMOnRamp(s_router.getOnRamp(remoteChainSelector)).getDynamicConfig().priceRegistry)
            .getFeeTokens();
    }

    function isSupportedChain(uint64 remoteChainSelector) public view returns (bool) {
        return s_remoteChainSelectors.contains(remoteChainSelector);
    }

    function isSenderEnabled(uint64 remoteChainSelector, Any2EVMAddress memory sender) public view returns (bool yes) {
        if (!isSupportedChain(remoteChainSelector)) return false;
        return s_remoteChainConfigs[remoteChainSelector]._addr.eq(sender);
    }

    function getSupportedChains() public view returns (uint64[] memory chains) {
        uint256[] memory values = s_remoteChainSelectors.values();
        assembly ("memory-safe") {
            chains := values
        }
    }

    function getCurrentChainSelector() external view returns (uint64) {
        return s_currentChainSelector;
    }

    function getRouter() external view returns (IRouterClientExtended router) {
        return s_router;
    }

    function getRmnProxy() public view returns (IRMN rmnProxy) {
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
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice Override this function in your implementation.
     * @param message Any2EVMMessage
     */
    function _ccipReceive(Client.Any2EVMMessage calldata message) internal virtual;

    function _addRemoteChain(uint64 remoteChainSelector, Any2EVMAddress memory addr)
        internal
        onlyRemoteChain(remoteChainSelector)
    {
        _requireNonZero(addr);
        _requireNonZero(remoteChainSelector);

        if (s_remoteChainSelectors.contains(remoteChainSelector)) revert ChainAlreadyEnabled(remoteChainSelector);
        s_remoteChainSelectors.add(remoteChainSelector);
        s_remoteChainConfigs[remoteChainSelector] =
            RemoteChainConfig({_chainSelector: remoteChainSelector, _addr: addr});

        emit RemoteChainEnabled(msg.sender, remoteChainSelector, addr);
    }

    function _removeRemoteChain(uint64 remoteChainSelector)
        internal
        onlyRemoteChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
    {
        s_remoteChainSelectors.remove(remoteChainSelector);
        delete s_remoteChainConfigs[remoteChainSelector];

        emit RemoteChainDisabled(msg.sender, remoteChainSelector);
    }

    function _sendDataPayFeeToken(
        uint64 remoteChainSelector,
        Any2EVMAddress memory receiver,
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

            uint256 overspent = fee - msg.value;
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

    function _getSendDataFee(
        uint64 remoteChainSelector,
        Any2EVMAddress memory receiver,
        bytes memory data,
        uint256 gasLimit,
        bool allowOutOfOrderExecution,
        address feeToken
    )
        internal
        view
        onlyRemoteChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
        returns (uint256 fee, Client.EVM2AnyMessage memory message)
    {
        message = Client.EVM2AnyMessage({
            receiver: receiver.raw(),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: gasLimit, allowOutOfOrderExecution: allowOutOfOrderExecution})
            ),
            feeToken: feeToken
        });

        fee = s_router.getFee(remoteChainSelector, message);
    }

    function _requireRemoteChain(uint64 remoteChainSelector) internal view {
        if (remoteChainSelector == s_currentChainSelector) revert OnlyRemoteChain(remoteChainSelector);
        if (!s_router.isChainSupported(remoteChainSelector)) revert ChainNotSupported(remoteChainSelector);
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

    function _requireNonZero(Any2EVMAddress memory addr) internal pure {
        if (addr.isNull()) revert ZeroAddressNotAllowed();
    }

    function _requireNotCursed(uint64 remoteChainSelector) internal view {
        if (s_rmnProxy.isCursed(bytes16(uint128(remoteChainSelector)))) revert CursedByRMN();
    }

    function _requireEnabledChain(uint64 remoteChainSelector) internal view {
        if (!isSupportedChain(remoteChainSelector)) revert NonExistentChain(remoteChainSelector);
    }

    function _requireEnabledSender(uint64 remoteChainSelector, Any2EVMAddress memory sender) internal view {
        if (!isSenderEnabled(remoteChainSelector, sender)) revert SenderNotEnabled(remoteChainSelector, sender);
    }
}
