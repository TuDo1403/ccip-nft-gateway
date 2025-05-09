// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISingleLockMintERC721Pool {
    error LengthMismatch(uint256 expected, uint256 actual);

    function withdrawLiquidity(address to, uint256[] calldata ids) external;

    function crossTransfer(uint64 remoteChainSelector, address to, uint256 id, address feeToken)
        external
        payable
        returns (bytes32 messageId);

    function crossBatchTransfer(uint64 remoteChainSelector, address to, uint256[] calldata ids, address feeToken)
        external
        payable
        returns (bytes32 messageId);
}
