// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ILockMintERC721Pool {
    error MintFailed(address minter, address to, uint256 id);
    error ERC721TransferFailed(address recipient, uint256 id);

    event CrossTransfer(
        address indexed srcFrom,
        address indexed dstTo,
        bytes32 indexed messageId,
        uint256[] ids,
        uint64 srcChainSelector,
        uint64 dstChainSelector
    );

    function estimateFee(address feeToken, uint64 remoteChainSelector, uint256 tokenCount)
        external
        view
        returns (uint256 fee);

    function estimateGasLimit(uint256 tokenCount) external view returns (uint256 gasLimit);
}
