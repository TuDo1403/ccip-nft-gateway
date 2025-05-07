// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TokenPoolAbstractUpgradeable} from "src/pools/TokenPoolAbstractUpgradeable.sol";
import {SingleTokenPoolUpgradeable} from "src/pools/SingleTokenPoolUpgradeable.sol";
import {PausableExtendedUpgradeable} from "src/extensions/PausableExtendedUpgradeable.sol";
import {RateLimitConsumerUpgradeable} from "src/extensions/RateLimitConsumerUpgradeable.sol";

import {IERC721Mintable} from "src/interfaces/external/IERC721Mintable.sol";
import {ILockMintERC721TokenPool} from "src/interfaces/pools/erc721/ILockMintERC721TokenPool.sol";
import {toAny, Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";
import {Pool} from "src/libraries/Pool.sol";

contract LockMintERC721TokenPool is
    RateLimitConsumerUpgradeable,
    PausableExtendedUpgradeable,
    SingleTokenPoolUpgradeable,
    ILockMintERC721TokenPool
{
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256[50] private __gap;

    EnumerableSet.AddressSet internal s_extStorages;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address token,
        uint32 fixedGas,
        uint32 dynamicGas,
        address router,
        uint64 currentChainSelector
    ) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        __RateLimitConsumer_init(admin);
        __PausableExtendedUpgradeable_init(admin);
        __SingleTokenPoolUpgradeable_init(admin, token, fixedGas, dynamicGas, router, currentChainSelector);
    }

    function withdrawLiquidity(address to, uint256[] calldata ids) external onlyRole(DEFAULT_ADMIN_ROLE) nonZero(to) {
        uint256 tokenCount = ids.length;
        for (uint256 i; i < tokenCount; ++i) {
            IERC721(s_token).transferFrom(address(this), to, ids[i]);
        }
    }

    function crossTransfer(uint64 remoteChainSelector, Any2EVMAddress calldata to, uint256 id, address feeToken)
        external
        payable
        returns (bytes32 messageId)
    {
        return _crossBatchTransfer(remoteChainSelector, to, _toSingletonArray(id), feeToken);
    }

    function crossBatchTransfer(
        uint64 remoteChainSelector,
        Any2EVMAddress calldata to,
        uint256[] calldata ids,
        address feeToken
    ) external payable returns (bytes32 messageId) {
        return _crossBatchTransfer(remoteChainSelector, to, ids, feeToken);
    }

    function updateExternalStorage(address extStorage, bool shouldAdd)
        external
        nonZero(extStorage)
        onlyRole(TOKEN_POOL_OWNER_ROLE)
    {
        if (shouldAdd) {
            if (!s_extStorages.add(extStorage)) revert ExtStorageAlreadyAdded(extStorage);
        } else {
            if (!s_extStorages.remove(extStorage)) revert ExtStorageNotAdded(extStorage);
        }

        emit ExternalStorageUpdated(msg.sender, extStorage, shouldAdd);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerableUpgradeable, TokenPoolAbstractUpgradeable)
        returns (bool)
    {
        return interfaceId == type(ILockMintERC721TokenPool).interfaceId || super.supportsInterface(interfaceId);
    }

    function estimateFee(address feeToken, uint64 remoteChainSelector, uint256 tokenCount)
        external
        view
        returns (uint256 fee)
    {
        Pool.ReleaseOrMint memory empty;
        empty.remotePoolData = abi.encode(new uint256[](tokenCount));

        (fee,) = _getSendDataFee({
            remoteChainSelector: remoteChainSelector,
            receiver: getRemotePool(remoteChainSelector),
            data: abi.encode(empty),
            gasLimit: estimateGasLimit(tokenCount),
            allowOutOfOrderExecution: true,
            feeToken: feeToken
        });
    }

    function estimateGasLimit(uint256 tokenCount) public view returns (uint256 gasLimit) {
        return s_fixedGas + s_dynamicGas * tokenCount;
    }

    function getExternalStorages() external view returns (address[] memory extStorages) {
        return s_extStorages.values();
    }

    function _crossBatchTransfer(
        uint64 remoteChainSelector,
        Any2EVMAddress calldata to,
        uint256[] memory ids,
        address feeToken
    ) internal returns (bytes32 messageId) {
        Pool.LockOrBurn memory lockOrBurn = Pool.LockOrBurn({
            remoteChainSelector: remoteChainSelector,
            originalSender: msg.sender,
            amount: ids.length,
            localToken: s_token,
            extraData: abi.encode(ids)
        });
        _lockOrBurn(lockOrBurn);

        _requireNonZero(to);
        Pool.ReleaseOrMint memory releaseOrMint = Pool.ReleaseOrMint({
            originalSender: toAny(msg.sender),
            remoteChainSelector: s_currentChainSelector,
            receiver: to,
            amount: lockOrBurn.amount,
            localToken: getRemoteToken(remoteChainSelector),
            remotePoolAddress: toAny(address(this)),
            remotePoolData: lockOrBurn.extraData
        });
        messageId = _sendDataPayFeeToken({
            remoteChainSelector: remoteChainSelector,
            receiver: getRemotePool(remoteChainSelector),
            data: abi.encode(releaseOrMint),
            gasLimit: estimateGasLimit(ids.length),
            allowOutOfOrderExecution: true,
            feeToken: feeToken
        });
    }

    function _ccipReceive(Client.Any2EVMMessage calldata message) internal virtual override {
        Pool.ReleaseOrMint memory releaseOrMint = abi.decode(message.data, (Pool.ReleaseOrMint));
        _releaseOrMint(releaseOrMint);

        emit CrossTransfer(
            releaseOrMint.originalSender,
            releaseOrMint.receiver.toEVM(),
            message.messageId,
            abi.decode(releaseOrMint.remotePoolData, (uint256[])),
            message.sourceChainSelector,
            s_currentChainSelector
        );
    }

    function _releaseOrMint(Pool.ReleaseOrMint memory releaseOrMint) internal virtual override whenNotPaused {
        uint256[] memory ids = abi.decode(releaseOrMint.remotePoolData, (uint256[]));
        _requireNonZero(ids.length);
        _requireEqualLength(ids.length, releaseOrMint.amount);

        address receiver = releaseOrMint.receiver.toEVM();
        address localToken = releaseOrMint.localToken.toEVM();

        _requireNonZero(receiver);
        _requireLocalToken(localToken);

        for (uint256 i; i < releaseOrMint.amount; ++i) {
            uint256 id = ids[i];
            address owned = _tryGetOwnerOf(localToken, id);

            if (owned == address(this) || s_extStorages.contains(owned)) {
                IERC721(localToken).transferFrom(owned, receiver, id);
            } else {
                IERC721Mintable(localToken).mint(receiver, id);
            }
        }

        _requireDelivered(localToken, receiver, ids);
        _consumeInboundRateLimit(releaseOrMint.remoteChainSelector, localToken, ids.length);
    }

    function _lockOrBurn(Pool.LockOrBurn memory lockOrBurn)
        internal
        virtual
        override
        whenNotPaused
        onlyLocalToken(lockOrBurn.localToken)
        onlyRemoteChain(lockOrBurn.remoteChainSelector)
        onlyEnabledChain(lockOrBurn.remoteChainSelector)
    {
        uint256[] memory ids = abi.decode(lockOrBurn.extraData, (uint256[]));
        _requireNonZero(ids.length);
        _requireEqualLength(ids.length, lockOrBurn.amount);

        for (uint256 i; i < lockOrBurn.amount; ++i) {
            IERC721(lockOrBurn.localToken).transferFrom(lockOrBurn.originalSender, address(this), ids[i]);
        }

        _requireDelivered(lockOrBurn.localToken, address(this), ids);
        _consumeOutboundRateLimit(lockOrBurn.remoteChainSelector, lockOrBurn.localToken, ids.length);
    }

    function _requireEqualLength(uint256 a, uint256 b) internal pure {
        if (a != b) revert LengthMismatch(a, b);
    }

    function _requireDelivered(address token, address recipient, uint256[] memory ids) internal view {
        uint256 tokenCount = ids.length;

        for (uint256 i; i < tokenCount; ++i) {
            if (_tryGetOwnerOf(token, ids[i]) != recipient) revert ERC721TransferFailed(recipient, ids[i]);
        }
    }

    function _tryGetOwnerOf(address token, uint256 id) internal view returns (address ownedBy) {
        try IERC721(token).ownerOf(id) returns (address by) {
            return by;
        } catch {
            // Handle the case where the token does not exist or is not an ERC721
            return address(0);
        }
    }

    function _toSingletonArray(uint256 id) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = id;
    }
}
