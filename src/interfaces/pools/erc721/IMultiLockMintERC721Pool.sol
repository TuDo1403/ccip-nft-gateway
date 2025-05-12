// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMultiLockMintERC721Pool {
    /**
     * @dev Withdraw the liquidity of the tokens in the pool.
     * Requirements:
     * - The caller must have `DEFAULT_ADMIN_ROLE`.
     * - The `localTokens` must be the same length as `tos` and `ids`.
     * - The `tos` must not be zero.
     * - `localTokens` must be supported by the pool.
     */
    function withdrawLiquidity(address[] calldata localTokens, address[] calldata tos, uint256[] calldata ids)
        external;

    /**
     * @dev Cross transfer a single token to the remote chain.
     * Requirements:
     * - `to` must not be zero.
     * - `id` must be approved for transfer.
     * - token fee should be query via `estimateFee` before calling this function.
     * - if `feeToken` is native (address(0)), the caller must send enough native tokens to cover the fee.
     * - if `feeToken` is ERC20, the caller must approve the pool to spend the fee token.
     * @return messageId The message ID of the cross transfer.
     */
    function crossTransfer(address localToken, uint64 remoteChainSelector, address to, uint256 id, address feeToken)
        external
        payable
        returns (bytes32 messageId);

    /**
     * @dev Cross transfer multiple tokens to the remote chain.
     * Requirements:
     * - `to` must not be zero.
     * - `ids` must be approved for transfer.
     * - token fee should be query via `estimateFee` before calling this function.
     * - if `feeToken` is native (address(0)), the caller must send enough native tokens to cover the fee.
     * - if `feeToken` is ERC20, the caller must approve the pool to spend the fee token.
     * @return messageId The message ID of the cross transfer.
     */
    function crossBatchTransfer(
        address localToken,
        uint64 remoteChainSelector,
        address to,
        uint256[] calldata ids,
        address feeToken
    ) external payable returns (bytes32 messageId);
}
