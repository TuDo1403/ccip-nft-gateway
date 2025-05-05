// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRMN} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRMN.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IRouterClientExtended} from "src/interfaces/IRouterClientExtended.sol";
import {ICCIPSenderReceiver} from "src/interfaces/extensions/ICCIPSenderReceiver.sol";

abstract contract CCIPSenderReceiverUpgradeable is Initializable, ICCIPSenderReceiver {
    uint256[50] private __gap1;

    uint64 internal s_currentChainSelector;
    IRMN internal s_rmnProxy;
    IRouterClientExtended internal s_router;

    uint256[50] private __gap2;

    modifier onlyEnabledSender(uint64 remoteChainSelector, address srcSender) {
        _requireEnabledSender(remoteChainSelector, srcSender);
        _;
    }

    modifier onlyEnabledChain(uint64 remoteChainSelector) {
        _requireEnabledChain(remoteChainSelector);
        _;
    }

    modifier onlyOtherChain(uint64 remoteChainSelector) {
        _requireOtherChain(remoteChainSelector);
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
    {
        __CCIPSenderReceiverUpgradeable_init_unchained(router, rmnProxy, currentChainSelector);
    }

    function __CCIPSenderReceiverUpgradeable_init_unchained(
        address router,
        address rmnProxy,
        uint64 currentChainSelector
    ) internal nonZero(router) nonZero(rmnProxy) onlyInitializing {
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
        onlyEnabledSender(message.sourceChainSelector, abi.decode(message.sender, (address)))
    {
        _ccipReceive(message);

        emit MessageReceived(abi.decode(message.sender, (address)), message.messageId);
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

    function isSupportedChain(uint64 remoteChainSelector) public view virtual returns (bool);

    function isSenderEnabled(uint64 remoteChainSelector, address srcSender) public view virtual returns (bool);

    /// @notice Override this function in your implementation.
    /// @param message Any2EVMMessage
    function _ccipReceive(Client.Any2EVMMessage calldata message) internal virtual;

    function _sendDataPayFeeToken(
        uint64 destChainSelector,
        address receiver,
        IERC20 feeToken,
        uint256 gasLimit,
        bool allowOutOfOrderExecution,
        bytes memory data
    ) internal notCursed(destChainSelector) returns (bytes32 messageId) {
        (uint256 fee, Client.EVM2AnyMessage memory message) =
            _getSendDataFee(destChainSelector, receiver, feeToken, gasLimit, allowOutOfOrderExecution, data);
        feeToken.transferFrom(msg.sender, address(this), fee);
        feeToken.approve(address(s_router), fee);

        messageId = s_router.ccipSend(destChainSelector, message);

        emit MessageSent(msg.sender, messageId);
    }

    function _getSendDataFee(
        uint64 destChainSelector,
        address receiver,
        IERC20 feeToken,
        uint256 gasLimit,
        bool allowOutOfOrderExecution,
        bytes memory data
    ) internal view returns (uint256 fee, Client.EVM2AnyMessage memory message) {
        if (address(feeToken) == address(0)) revert NativeFeeNotAllowed();

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: data,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({gasLimit: gasLimit, allowOutOfOrderExecution: allowOutOfOrderExecution})
            ),
            feeToken: address(feeToken)
        });

        fee = s_router.getFee(destChainSelector, message);
    }

    function _requireOtherChain(uint64 remoteChainSelector) internal view {
        if (remoteChainSelector == s_currentChainSelector) revert OnlyOtherChain(remoteChainSelector);
    }

    function _requireRouter() internal view {
        if (msg.sender != address(s_router)) revert InvalidRouter(address(s_router), msg.sender);
    }

    function _requireNonZero(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddressNotAllowed();
    }

    function _requireNotCursed(uint64 remoteChainSelector) internal view {
        if (s_rmnProxy.isCursed(bytes16(uint128(remoteChainSelector)))) revert CursedByRMN();
    }

    function _requireEnabledChain(uint64 remoteChainSelector) internal view {
        if (!isSupportedChain(remoteChainSelector)) revert NonExistentChain(remoteChainSelector);
    }

    function _requireEnabledSender(uint64 remoteChainSelector, address srcSender) internal view {
        if (!isSenderEnabled(remoteChainSelector, srcSender)) revert SenderNotEnabled(remoteChainSelector, srcSender);
    }
}
