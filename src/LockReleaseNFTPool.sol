// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ILockReleaseNFTPool} from "src/interfaces/ILockReleaseNFTPool.sol";
import {LibNFTTransferHandler} from "src/libraries/LibNFTTransferHandler.sol";

contract LockReleaseNFTPool is Ownable2Step, ReentrancyGuard, ERC165, ERC1155Holder, ILockReleaseNFTPool {
    using LibNFTTransferHandler for address;

    address internal immutable i_linkToken;
    address internal immutable i_nftAddress;
    address internal immutable i_ccipRouter;
    address internal immutable i_roninGateway;
    uint64 internal immutable i_currentChainSelector;

    mapping(uint64 dstChainSelector => PoolParam poolParam) internal _srcPool;

    modifier nonZeroAddress(address addr) {
        _requireNonZeroAddress(addr);
        _;
    }

    modifier onlyRouter() {
        _requireRouter();
        _;
    }

    modifier onlyOtherChain(uint64 chainSelector) {
        _requireOtherChain(chainSelector);
        _;
    }

    modifier onlyEnabledChain(uint64 chainSelector) {
        _requireEnabledChain(chainSelector);
        _;
    }

    modifier onlyEnabledSender(uint64 srcChainSelector, address srcSender) {
        _requireEnabledSender(srcChainSelector, srcSender);
        _;
    }

    constructor(
        address ccipRouter,
        address roninGateway,
        address nftAddress,
        uint64 currentChainSelector,
        address linkToken
    ) Ownable(msg.sender) {
        _requireNonZeroAddress(ccipRouter);
        _requireNonZeroAddress(roninGateway);
        _requireNonZeroAddress(nftAddress);
        _requireNonZeroAddress(linkToken);

        i_roninGateway = roninGateway;
        i_ccipRouter = ccipRouter;
        i_nftAddress = nftAddress;
        i_linkToken = linkToken;
        i_currentChainSelector = currentChainSelector;
    }

    function enableChain(uint64 srcChainSelector, address pool, bytes calldata extraArgs)
        external
        onlyOwner
        nonZeroAddress(pool)
        onlyOtherChain(srcChainSelector)
    {
        if (srcChainSelector == i_currentChainSelector) revert OnlyOtherChain(srcChainSelector);

        _srcPool[srcChainSelector]._pool = pool;
        _srcPool[srcChainSelector]._extraArgs = extraArgs;

        emit ChainEnabled(srcChainSelector, pool, extraArgs);
    }

    function disableChain(uint64 srcChainSelector) external onlyOwner onlyOtherChain(srcChainSelector) {
        delete _srcPool[srcChainSelector];

        emit ChainDisabled(srcChainSelector);
    }

    function crossChainTransfer(
        address to,
        uint256 tokenId,
        uint256 quantity,
        uint64 dstChainSelector,
        PayFeesIn payFeesIn
    ) external payable nonReentrant nonZeroAddress(to) onlyEnabledChain(dstChainSelector) returns (bytes32 messageId) {
        (bool isERC721,) = i_nftAddress.validateERC721OrERC1155(quantity);

        bool sent = isERC721
            ? i_nftAddress.tryTransferFromERC721({from: msg.sender, to: address(this), id: tokenId})
            : i_nftAddress.tryTransferFromERC1155({from: msg.sender, to: address(this), id: tokenId, amount: quantity});
        if (!sent) revert NFTLockFailed(msg.sender, address(this), tokenId, quantity);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_srcPool[dstChainSelector]._pool),
            data: abi.encode(msg.sender, to, tokenId, quantity),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: _srcPool[dstChainSelector]._extraArgs,
            feeToken: payFeesIn == PayFeesIn.LINK ? address(i_linkToken) : address(0)
        });

        uint256 fee = IRouterClient(i_ccipRouter).getFee(dstChainSelector, message);

        if (payFeesIn == PayFeesIn.LINK) {
            IERC20(i_linkToken).transferFrom(msg.sender, address(this), fee);
            IERC20(i_linkToken).approve(i_ccipRouter, fee);
            delete fee; // Delete the fee variable to avoid reusing it
        } else {
            if (msg.value < fee) revert InsufficientBalance(PayFeesIn.Native, msg.value, fee);

            uint256 overspent = msg.value - fee;
            if (overspent > 0) {
                (bool success,) = msg.sender.call{value: overspent}("");
                if (!success) revert RefundFailed(msg.sender, overspent);
                emit Refunded(msg.sender, overspent);
            }
        }

        messageId = IRouterClient(i_ccipRouter).ccipSend{value: fee}(dstChainSelector, message);

        emit CrossChainSent(msg.sender, to, tokenId, quantity, i_currentChainSelector, dstChainSelector);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155Holder, ERC165) returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function ccipReceive(Client.Any2EVMMessage calldata message)
        external
        onlyRouter
        nonReentrant
        onlyEnabledChain(message.sourceChainSelector)
        onlyEnabledSender(message.sourceChainSelector, abi.decode(message.sender, (address)))
    {
        uint64 srcChainSelector = message.sourceChainSelector;

        (address from, address to, uint256 tokenId, uint256 quantity) =
            abi.decode(message.data, (address, address, uint256, uint256));

        (bool isERC721,) = i_nftAddress.validateERC721OrERC1155(quantity);
        bool sent = isERC721
            ? i_nftAddress.tryTransferOutOrMintERC721({nftStorage: i_roninGateway, to: to, id: tokenId})
            : i_nftAddress.tryTransferOutOrMintERC1155({nftStorage: i_roninGateway, to: to, id: tokenId, amount: quantity});
        if (!sent) revert NFTReleaseFailed(from, to, tokenId, quantity);

        emit CrossChainReceived(from, to, tokenId, quantity, srcChainSelector, i_currentChainSelector);
    }

    function getLinkToken() external view returns (address) {
        return i_linkToken;
    }

    function getNFTAddress() external view returns (address) {
        return i_nftAddress;
    }

    function getCCIPRouter() external view returns (address) {
        return i_ccipRouter;
    }

    function getRoninGateway() external view returns (address) {
        return i_roninGateway;
    }

    function getCurrentChainSelector() external view returns (uint64) {
        return i_currentChainSelector;
    }

    function getSourcePool(uint64 srcChainSelector) external view returns (address poolAddr, bytes memory extraArgs) {
        return (_srcPool[srcChainSelector]._pool, _srcPool[srcChainSelector]._extraArgs);
    }

    function _requireNonZeroAddress(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddress();
    }

    function _requireRouter() internal view {
        if (msg.sender != i_ccipRouter) revert InvalidRouter(i_ccipRouter, msg.sender);
    }

    function _requireOtherChain(uint64 chainSelector) internal view {
        if (chainSelector == i_currentChainSelector) revert OnlyOtherChain(chainSelector);
    }

    function _requireEnabledSender(uint64 srcChainSelector, address srcSender) internal view {
        if (_srcPool[srcChainSelector]._pool != srcSender) revert SenderNotEnabled(srcChainSelector, srcSender);
    }

    function _requireEnabledChain(uint64 chainSelector) internal view {
        if (_srcPool[chainSelector]._pool == address(0)) revert ChainNotEnabled(chainSelector);
    }
}
