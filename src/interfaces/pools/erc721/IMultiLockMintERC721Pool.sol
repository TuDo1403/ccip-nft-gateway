// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMultiLockMintERC721Pool {
    function withdrawLiquidity(address localToken, address to, uint256[] calldata ids) external;

    function crossTransfer(address localToken, uint64 remoteChainSelector, address to, uint256 id, address feeToken)
        external
        payable
        returns (bytes32 messageId);

    function crossBatchTransfer(
        address localToken,
        uint64 remoteChainSelector,
        address to,
        uint256[] calldata ids,
        address feeToken
    ) external payable returns (bytes32 messageId);
}
