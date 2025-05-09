// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {TokenPool} from "src/pools/TokenPool.sol";
import {SingleTokenPool} from "src/pools/SingleTokenPool.sol";
import {LockMintERC721Pool} from "src/pools/erc721/LockMintERC721Pool.sol";

import {ISingleLockMintERC721Pool} from "src/interfaces/pools/erc721/ISingleLockMintERC721Pool.sol";
import {Pool} from "src/libraries/Pool.sol";

contract SingleLockMintERC721Pool is LockMintERC721Pool, SingleTokenPool, ISingleLockMintERC721Pool {
    string public constant override typeAndVersion = "SingleLockMintERC721Pool 1.0.0";
    
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

    function withdrawLiquidity(address to, uint256[] calldata ids) external onlyRole(DEFAULT_ADMIN_ROLE) nonZero(to) {
        uint256 tokenCount = ids.length;
        for (uint256 i; i < tokenCount; ++i) {
            IERC721(getToken()).transferFrom(address(this), to, ids[i]);
        }
    }

    function crossTransfer(uint64 remoteChainSelector, address to, uint256 id, address feeToken)
        external
        payable
        returns (bytes32 messageId)
    {
        return _crossBatchTransfer(remoteChainSelector, to, _toSingletonArray(id), feeToken);
    }

    function crossBatchTransfer(uint64 remoteChainSelector, address to, uint256[] calldata ids, address feeToken)
        external
        payable
        returns (bytes32 messageId)
    {
        return _crossBatchTransfer(remoteChainSelector, to, ids, feeToken);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(TokenPool, LockMintERC721Pool)
        returns (bool)
    {
        return interfaceId == type(ISingleLockMintERC721Pool).interfaceId || super.supportsInterface(interfaceId);
    }

    function _crossBatchTransfer(uint64 remoteChainSelector, address to, uint256[] memory ids, address feeToken)
        internal
        nonZero(to)
        returns (bytes32 messageId)
    {
        bytes memory data = abi.encode(ids);
        _lockOrBurn(
            Pool.LockOrBurn({remoteChainSelector: remoteChainSelector, localToken: getToken(), extraData: data})
        );

        address remoteToken = getRemoteToken(remoteChainSelector);
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

    function _requireEqualLength(uint256 a, uint256 b) internal pure {
        if (a != b) revert LengthMismatch(a, b);
    }

    function _toSingletonArray(uint256 id) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = id;
    }
}
