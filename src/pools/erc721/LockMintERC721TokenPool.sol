// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TokenPoolUpgradeable} from "src/pools/TokenPoolUpgradeable.sol";
import {RateLimitConsumerUpgradeable} from "src/extensions/RateLimitConsumerUpgradeable.sol";

import {IERC721Mintable} from "src/interfaces/external/IERC721Mintable.sol";
import {IExtStorage} from "src/interfaces/external/IExtStorage.sol";
import {ILockMintERC721TokenPool} from "src/interfaces/pools/erc721/ILockMintERC721TokenPool.sol";

contract LockMintERC721TokenPool is RateLimitConsumerUpgradeable, TokenPoolUpgradeable, ILockMintERC721TokenPool {
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
        address rmnProxy,
        uint64 currentChainSelector
    ) external override initializer {
        __RateLimitConsumer_init(admin);
        __TokenPoolUpgradeable_init(admin, token, fixedGas, dynamicGas, router, rmnProxy, currentChainSelector);
    }

    function crossBatchTransfer(address to, uint256[] calldata ids, uint64 remoteChainSelector, IERC20 feeToken)
        external
        nonZero(to)
        returns (bytes32 messageId)
    {
        LockOrBurn memory lockOrBurn = LockOrBurn({
            receiver: abi.encode(to),
            remoteChainSelector: remoteChainSelector,
            originalSender: msg.sender,
            amount: ids.length,
            localToken: s_token,
            extraData: abi.encode(ids)
        });
        _lockOrBurn(lockOrBurn);

        messageId = _sendDataPayFeeToken({
            remoteChainSelector: remoteChainSelector,
            receiver: getRemotePool(remoteChainSelector),
            feeToken: feeToken,
            gasLimit: estimateGasLimit(ids.length),
            allowOutOfOrderExecution: true,
            data: abi.encode(
                ReleaseOrMint({
                    originalSender: abi.encode(msg.sender),
                    remoteChainSelector: s_currentChainSelector,
                    receiver: to,
                    amount: lockOrBurn.amount,
                    localToken: getRemoteToken(remoteChainSelector),
                    remotePoolAddress: abi.encode(address(this)),
                    remotePoolData: lockOrBurn.extraData
                })
            )
        });
    }

    function updateExternalStorage(address extStorage, bool shouldAdd)
        external
        nonZero(extStorage)
        onlyRole(TOKEN_POOL_OWNER)
    {
        if (shouldAdd) {
            if (s_extStorages.contains(extStorage)) revert ExtStorageAlreadyAdded(extStorage);
            s_extStorages.add(extStorage);
        } else {
            if (!s_extStorages.contains(extStorage)) revert ExtStorageNotAdded(extStorage);
            s_extStorages.remove(extStorage);
        }

        emit ExternalStorageUpdated(msg.sender, extStorage, shouldAdd);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerableUpgradeable, TokenPoolUpgradeable)
        returns (bool)
    {
        return interfaceId == type(ILockMintERC721TokenPool).interfaceId || super.supportsInterface(interfaceId);
    }

    function estimateFee(IERC20 feeToken, uint64 remoteChainSelector, uint256 tokenCount)
        external
        view
        onlyRemoteChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
        returns (uint256 fee)
    {
        (fee,) = _getSendDataFee({
            remoteChainSelector: remoteChainSelector,
            receiver: getRemotePool(remoteChainSelector),
            feeToken: feeToken,
            gasLimit: estimateGasLimit(tokenCount),
            allowOutOfOrderExecution: true,
            data: abi.encode(address(0), address(0), new uint256[](tokenCount))
        });
    }

    function estimateGasLimit(uint256 tokenCount) public view returns (uint256 gasLimit) {
        return s_fixedGas + s_dynamicGas * tokenCount;
    }

    function getExternalStorages() external view returns (address[] memory extStorages) {
        return s_extStorages.values();
    }

    function _ccipReceive(Client.Any2EVMMessage calldata message) internal virtual override {
        ReleaseOrMint memory releaseOrMint = abi.decode(message.data, (ReleaseOrMint));
        _releaseOrMint(releaseOrMint);

        emit CrossTransfer(
            releaseOrMint.originalSender,
            releaseOrMint.receiver,
            message.messageId,
            abi.decode(releaseOrMint.remotePoolData, (uint256[])),
            message.sourceChainSelector,
            s_currentChainSelector
        );
    }

    function _releaseOrMint(ReleaseOrMint memory releaseOrMint)
        internal
        virtual
        override
        nonZero(releaseOrMint.receiver)
        onlyLocalToken(releaseOrMint.localToken)
    {
        uint256[] memory ids = abi.decode(releaseOrMint.remotePoolData, (uint256[]));
        _requireNonZero(ids.length);
        _requireEqualLength(ids.length, releaseOrMint.amount);

        address[] memory extStorages = s_extStorages.values();
        uint256 extStorageCount = extStorages.length;

        for (uint256 i; i < releaseOrMint.amount; ++i) {
            uint256 id = ids[i];
            address owned = _tryGetOwnerOf(releaseOrMint.localToken, id);

            if (s_extStorages.contains(owned) || owned == address(this)) {
                IERC721(releaseOrMint.localToken).transferFrom(owned, releaseOrMint.receiver, id);
            } else {
                try IERC721Mintable(releaseOrMint.localToken).mint(releaseOrMint.receiver, id) {}
                catch {
                    if (extStorageCount == 0) revert MintFailed(address(this), releaseOrMint.receiver, id);

                    for (uint256 j; j < extStorageCount; ++j) {
                        try IExtStorage(extStorages[i]).mintFor(releaseOrMint.localToken, releaseOrMint.receiver, id) {
                            break;
                        } catch {
                            if (j == extStorageCount - 1) revert MintFailed(extStorages[i], releaseOrMint.receiver, id);
                        }
                    }
                }
            }
        }

        _requireDelivered(releaseOrMint.localToken, releaseOrMint.receiver, ids);
        _consumeInboundRateLimit(releaseOrMint.remoteChainSelector, releaseOrMint.localToken, ids.length);
    }

    function _lockOrBurn(LockOrBurn memory lockOrBurn)
        internal
        virtual
        override
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
}
