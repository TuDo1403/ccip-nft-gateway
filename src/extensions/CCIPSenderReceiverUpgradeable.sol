// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRMN} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRMN.sol";
import {IWrappedNative} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IWrappedNative.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IRouterClientExtended} from "src/interfaces/IRouterClientExtended.sol";
import {ICCIPSenderReceiver} from "src/interfaces/extensions/ICCIPSenderReceiver.sol";

abstract contract CCIPSenderReceiverUpgradeable is Initializable, ICCIPSenderReceiver {
    using EnumerableSet for EnumerableSet.UintSet;

    uint256[50] private __gap1;

    uint64 internal s_currentChainSelector;
    IRMN internal s_rmnProxy;
    IRouterClientExtended internal s_router;
    EnumerableSet.UintSet internal s_remoteChainSelectors;
    mapping(uint64 remoteChainSelector => RemoteChainConfig remoteChainConfig) internal s_remoteChainConfigs;

    uint256[50] private __gap2;

    modifier onlyEnabledSender(uint64 remoteChainSelector, bytes calldata sender) {
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

    function __CCIPSenderReceiverUpgradeable_init(address router, address rmnProxy, uint64 currentChainSelector)
        internal
        onlyInitializing
    {
        __CCIPSenderReceiverUpgradeable_init_unchained(router, rmnProxy, currentChainSelector);
    }

    function __CCIPSenderReceiverUpgradeable_init_unchained(
        address router,
        address rmnProxy,
        uint64 currentChainSelector
    ) internal nonZero(router) nonZero(rmnProxy) onlyInitializing {
        _requireNonZero(currentChainSelector);

        s_router = IRouterClientExtended(router);
        s_rmnProxy = IRMN(rmnProxy);
        s_currentChainSelector = currentChainSelector;
    }

    /// @inheritdoc IAny2EVMMessageReceiver
    function ccipReceive(Client.Any2EVMMessage calldata message)
        external
        override
        onlyRouter
        notCursed(message.sourceChainSelector)
        onlyEnabledChain(message.sourceChainSelector)
        onlyEnabledSender(message.sourceChainSelector, message.sender)
    {
        _ccipReceive(message);

        emit MessageReceived(abi.decode(message.sender, (address)), message.messageId);
    }

    function isSupportedChain(uint64 remoteChainSelector) public view returns (bool) {
        return s_remoteChainSelectors.contains(remoteChainSelector);
    }

    function isSenderEnabled(uint64 remoteChainSelector, bytes calldata sender) public view returns (bool yes) {
        if (!isSupportedChain(remoteChainSelector)) return false;
        return keccak256(s_remoteChainConfigs[remoteChainSelector]._addr) == keccak256(sender);
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

    function _addRemoteChain(uint64 remoteChainSelector, bytes memory addr)
        internal
        onlyRemoteChain(remoteChainSelector)
    {
        _requireNonZero(addr.length);
        _requireNonZero(remoteChainSelector);

        bytes32 addressHash = keccak256(addr);

        if (s_remoteChainSelectors.contains(remoteChainSelector)) revert ChainAlreadyEnabled(remoteChainSelector);
        s_remoteChainSelectors.add(remoteChainSelector);
        s_remoteChainConfigs[remoteChainSelector] =
            RemoteChainConfig({_chainSelector: remoteChainSelector, _addr: addr});

        emit RemoteChainEnabled(msg.sender, remoteChainSelector, addressHash);
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
        address receiver,
        IERC20 feeToken,
        uint256 gasLimit,
        bool allowOutOfOrderExecution,
        bytes memory data
    ) internal notCursed(remoteChainSelector) nonZero(receiver) returns (bytes32 messageId) {
        _requireNonZero(gasLimit);
        _requireNonZero(data.length);

        (uint256 fee, Client.EVM2AnyMessage memory message) =
            _getSendDataFee(remoteChainSelector, receiver, feeToken, gasLimit, allowOutOfOrderExecution, data);

        if (address(feeToken) == address(0)) {
            if (msg.value < fee) revert InsufficientAllowance(fee, msg.value);

            IWrappedNative wnt = IWrappedNative(s_router.getWrappedNative());
            wnt.deposit{value: fee}();
            feeToken = IERC20(address(wnt));

            uint256 overspent = fee - msg.value;
            if (overspent > 0) {
                // solhint-disable-next-line avoid-low-level-calls
                (bool success,) = msg.sender.call{value: overspent}("");
                if (!success) revert RefundFailed(msg.sender, overspent);
                emit Refunded(msg.sender, overspent);
            }
        } else {
            if (msg.value != 0) revert MsgValueNotAllowed(msg.value);
            feeToken.transferFrom(msg.sender, address(this), fee);
        }

        feeToken.approve(address(s_router), fee);

        messageId = s_router.ccipSend(remoteChainSelector, message);

        emit MessageSent(msg.sender, messageId);
    }

    function _getSendDataFee(
        uint64 remoteChainSelector,
        address receiver,
        IERC20 feeToken,
        uint256 gasLimit,
        bool allowOutOfOrderExecution,
        bytes memory data
    )
        internal
        view
        onlyRemoteChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
        returns (uint256 fee, Client.EVM2AnyMessage memory message)
    {
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: gasLimit, allowOutOfOrderExecution: allowOutOfOrderExecution})
            ),
            feeToken: address(feeToken)
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

    function _requireNotCursed(uint64 remoteChainSelector) internal view {
        if (s_rmnProxy.isCursed(bytes16(uint128(remoteChainSelector)))) revert CursedByRMN();
    }

    function _requireEnabledChain(uint64 remoteChainSelector) internal view {
        if (!isSupportedChain(remoteChainSelector)) revert NonExistentChain(remoteChainSelector);
    }

    function _requireEnabledSender(uint64 remoteChainSelector, bytes memory sender) internal view {
        bytes32 senderHash = keccak256(sender);
        if (keccak256(s_remoteChainConfigs[remoteChainSelector]._addr) != senderHash) {
            revert SenderNotEnabled(remoteChainSelector, senderHash);
        }
    }
}
