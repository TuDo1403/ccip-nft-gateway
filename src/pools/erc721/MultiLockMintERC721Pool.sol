// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {TokenPool} from "src/pools/TokenPool.sol";
import {MultiTokenPool} from "src/pools/MultiTokenPool.sol";
import {LockMintERC721Pool} from "src/pools/erc721/LockMintERC721Pool.sol";

import {IMultiLockMintERC721Pool} from "src/interfaces/pools/erc721/IMultiLockMintERC721Pool.sol";
import {Pool} from "src/libraries/Pool.sol";

contract MultiLockMintERC721Pool is MultiTokenPool, LockMintERC721Pool, IMultiLockMintERC721Pool {
    string public constant override typeAndVersion = "MultiLockMintERC721Pool 1.0.0";

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, uint32 fixedGas, uint32 dynamicGas, address router, uint64 currentChainSelector)
        external
        initializer
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        __PausableExtended_init(admin);
        __RateLimitConsumer_init(admin);
        __SharedStorageConsumer_init(admin);
        __TokenPool_init(admin, fixedGas, dynamicGas, router, currentChainSelector);
    }

    function withdrawLiquidity(address[] calldata localTokens, address[] calldata tos, uint256[] calldata ids)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _requireEqualLength(localTokens.length, ids.length);
        _requireEqualLength(localTokens.length, tos.length);
        uint256 tokenCount = ids.length;
        _requireNonZero(tokenCount);

        for (uint256 i; i < tokenCount; ++i) {
            _requireLocalToken(localTokens[i]);
            _requireNonZero(tos[i]);

            IERC721(localTokens[i]).transferFrom(address(this), tos[i], ids[i]);
        }
    }

    function crossTransfer(address localToken, uint64 remoteChainSelector, address to, uint256 id, address feeToken)
        external
        payable
        returns (bytes32 messageId)
    {
        return _crossBatchTransfer(localToken, remoteChainSelector, to, _toSingletonArray(id), feeToken);
    }

    function crossBatchTransfer(
        address localToken,
        uint64 remoteChainSelector,
        address to,
        uint256[] calldata ids,
        address feeToken
    ) external payable returns (bytes32 messageId) {
        return _crossBatchTransfer(localToken, remoteChainSelector, to, ids, feeToken);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(MultiTokenPool, LockMintERC721Pool)
        returns (bool)
    {
        return interfaceId == type(IMultiLockMintERC721Pool).interfaceId
            || LockMintERC721Pool.supportsInterface(interfaceId) || MultiTokenPool.supportsInterface(interfaceId);
    }

    function _releaseOrMint(Pool.ReleaseOrMint memory releaseOrMint)
        internal
        virtual
        override(TokenPool, LockMintERC721Pool)
    {
        // Prevent the case when localToken is mapped to many remote chains
        // and the message is sent to from the remote chain that is unmapped with the localToken
        _requireNonZero(getRemoteToken(releaseOrMint.localToken, releaseOrMint.remoteChainSelector));
        super._releaseOrMint(releaseOrMint);
    }

    function _crossBatchTransfer(
        address localToken,
        uint64 remoteChainSelector,
        address to,
        uint256[] memory ids,
        address feeToken
    ) internal nonZero(to) returns (bytes32 messageId) {
        bytes memory data = abi.encode(ids);
        _lockOrBurn(
            Pool.LockOrBurn({remoteChainSelector: remoteChainSelector, localToken: localToken, extraData: data})
        );

        address remoteToken = getRemoteToken(localToken, remoteChainSelector);
        _requireNonZero(remoteToken);
        messageId = _sendDataPayFeeToken({
            remoteChainSelector: remoteChainSelector,
            receiver: getRemotePool(remoteChainSelector),
            data: abi.encode(
                Pool.ReleaseOrMint({
                    originalSender: msg.sender,
                    remoteChainSelector: getCurrentChainSelector(),
                    receiver: to,
                    localToken: remoteToken,
                    remotePoolAddress: address(this),
                    remotePoolData: data
                })
            ),
            gasLimit: estimateGasLimit(ids.length),
            allowOutOfOrderExecution: true,
            feeToken: feeToken
        });
    }

    function _toSingletonArray(uint256 id) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = id;
    }
}
