// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Mintable} from "src/interfaces/external/IERC721Mintable.sol";

import {PausableExtendedUpgradeable} from "src/extensions/PausableExtendedUpgradeable.sol";
import {RateLimitConsumerUpgradeable} from "src/extensions/RateLimitConsumerUpgradeable.sol";
import {SharedStorageConsumerUpgradeable} from "src/extensions/SharedStorageConsumerUpgradeable.sol";
import {TokenPool} from "src/pools/TokenPool.sol";
import {ILockMintERC721Pool} from "src/interfaces/pools/erc721/ILockMintERC721Pool.sol";
import {Pool} from "src/libraries/Pool.sol";

abstract contract LockMintERC721Pool is
    PausableExtendedUpgradeable,
    RateLimitConsumerUpgradeable,
    SharedStorageConsumerUpgradeable,
    TokenPool,
    ILockMintERC721Pool
{
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
        (uint32 fixedGas, uint32 dynamicGas) = getGasLimitConfig();
        return fixedGas + dynamicGas * tokenCount;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(PausableExtendedUpgradeable, RateLimitConsumerUpgradeable, SharedStorageConsumerUpgradeable, TokenPool)
        returns (bool)
    {
        return interfaceId == type(ILockMintERC721Pool).interfaceId || TokenPool.supportsInterface(interfaceId)
            || SharedStorageConsumerUpgradeable.supportsInterface(interfaceId)
            || RateLimitConsumerUpgradeable.supportsInterface(interfaceId)
            || PausableExtendedUpgradeable.supportsInterface(interfaceId);
    }

    function _ccipReceive(Client.Any2EVMMessage calldata message) internal virtual override {
        Pool.ReleaseOrMint memory releaseOrMint = abi.decode(message.data, (Pool.ReleaseOrMint));
        _releaseOrMint(releaseOrMint);

        emit CrossTransfer(
            releaseOrMint.originalSender,
            releaseOrMint.receiver,
            message.messageId,
            abi.decode(releaseOrMint.remotePoolData, (uint256[])),
            message.sourceChainSelector,
            getCurrentChainSelector()
        );
    }

    function _releaseOrMint(Pool.ReleaseOrMint memory releaseOrMint) internal virtual override whenNotPaused {
        uint256[] memory ids = abi.decode(releaseOrMint.remotePoolData, (uint256[]));
        uint256 tokenCount = ids.length;
        _requireNonZero(tokenCount);

        _requireNonZero(releaseOrMint.receiver);
        _requireLocalToken(releaseOrMint.localToken);

        for (uint256 i; i < tokenCount; ++i) {
            uint256 id = ids[i];
            address owned = _tryGetOwnerOf(releaseOrMint.localToken, id);

            if (owned == address(this) || isSharedStorage(owned)) {
                IERC721(releaseOrMint.localToken).transferFrom(owned, releaseOrMint.receiver, id);
            } else {
                IERC721Mintable(releaseOrMint.localToken).mint(releaseOrMint.receiver, id);
            }
        }

        _requireDelivered(releaseOrMint.localToken, releaseOrMint.receiver, ids);
        _consumeInboundRateLimit(releaseOrMint.remoteChainSelector, releaseOrMint.localToken, tokenCount);
    }

    function _lockOrBurn(Pool.LockOrBurn memory lockOrBurn)
        internal
        virtual
        override
        whenNotPaused
        onlyLocalToken(lockOrBurn.localToken)
        onlyEnabledChain(lockOrBurn.remoteChainSelector)
    {
        uint256[] memory ids = abi.decode(lockOrBurn.extraData, (uint256[]));
        uint256 tokenCount = ids.length;
        _requireNonZero(tokenCount);

        for (uint256 i; i < tokenCount; ++i) {
            IERC721(lockOrBurn.localToken).transferFrom(msg.sender, address(this), ids[i]);
        }

        _requireDelivered(lockOrBurn.localToken, address(this), ids);
        _consumeOutboundRateLimit(lockOrBurn.remoteChainSelector, lockOrBurn.localToken, tokenCount);
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
