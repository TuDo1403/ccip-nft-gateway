// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ILockMintERC721Pool {
    /// @dev Throws when ccip's message source chain selector does not match with decoded input.
    error RemoteChainSelectorNotMatch(uint64 expected, uint64 actual);
    /// @dev Throws when ccip's message original sender does not match with current pool config.
    error RemotePoolNotMatch(address expected, address actual);
    /// @dev Throws when failed to mint token.
    error MintFailed(address minter, address to, uint256 id);
    /// @dev Throws when failed to transfer token.
    error ERC721TransferFailed(address recipient, uint256 id);

    /// @dev Emit when successfully bridged nfts for user.
    event CrossTransfer(
        address indexed srcFrom,
        address indexed dstTo,
        bytes32 indexed messageId,
        uint256[] ids,
        uint64 srcChainSelector,
        uint64 dstChainSelector
    );

    /**
     * @dev Estimate the fee to pay for CCIP protocol to bridge the tokens.
     * @param feeToken The token to pay the fee.
     * @param remoteChainSelector The chain selector of the destination chain.
     * @param tokenCount The number of tokens to bridge.
     * @return fee The estimated fee in the feeToken.
     */
    function estimateFee(address feeToken, uint64 remoteChainSelector, uint256 tokenCount)
        external
        view
        returns (uint256 fee);

    /**
     * @dev Estimate the gas limit for transferring `tokenCount` tokens.
     */
    function estimateGasLimit(uint256 tokenCount) external view returns (uint256 gasLimit);
}
