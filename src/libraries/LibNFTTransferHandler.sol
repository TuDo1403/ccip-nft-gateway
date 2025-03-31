// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IERC1155Mintable} from "src/interfaces/ext/IERC1155Mintable.sol";
import {IERC721Mintable} from "src/interfaces/ext/IERC721Mintable.sol";

library LibNFTTransferHandler {
    using ERC165Checker for address;

    error TokenNotERC721OrERC1155(address token, uint256 quantity);
    error TokenIsBothERC721AndERC1155(address token, uint256 quantity);

    /**
     * @dev Checks if the token is ERC721 or ERC1155.
     */
    function validateERC721OrERC1155(address token, uint256 quantity)
        internal
        view
        returns (bool isERC721, bool isERC1155)
    {
        isERC721 = token.supportsInterface(type(IERC721).interfaceId) && quantity == 0;
        isERC1155 = token.supportsInterface(type(IERC1155).interfaceId) && quantity > 0;

        if (!isERC721 && !isERC1155) revert TokenNotERC721OrERC1155(token, quantity);
        if (isERC721 && isERC1155) revert TokenIsBothERC721AndERC1155(token, quantity);
    }

    /**
     *      TRANSFER ERC-721
     */

    /**
     * @dev Transfers the ERC721 token out. If the transfer failed, mints the ERC721.
     * @return success Returns `false` if both transfer and mint are failed.
     */
    function tryTransferOutOrMintERC721(address token, address nftStorage, address to, uint256 id)
        internal
        returns (bool success)
    {
        success = tryTransferFromERC721(token, nftStorage, to, id);
        if (!success) {
            // Skip minting if the token is already owned by the NFT storage contract.
            // This means that the pool is hasn't been granted approval to transfer the token.
            if (_tryGetOwnerOf(token, id) == nftStorage) return false;

            return _tryMintERC721(token, to, id);
        }
    }

    /**
     * @dev Transfers ERC721 token and returns the result.
     */
    function tryTransferFromERC721(address token, address from, address to, uint256 id)
        internal
        returns (bool success)
    {
        (success,) = token.call(abi.encodeCall(IERC721.transferFrom, (from, to, id)));
    }

    /**
     * @dev Mints ERC721 token and returns the result.
     */
    function _tryMintERC721(address token, address to, uint256 id) private returns (bool success) {
        (success,) = token.call(abi.encodeCall(IERC721Mintable.mint, (to, id)));
    }

    /**
     *      TRANSFER ERC-1155
     */

    /**
     * @dev Transfers the ERC1155 token out. If the transfer failed, mints the ERC11555.
     * @return success Returns `false` if both transfer and mint are failed.
     */
    function tryTransferOutOrMintERC1155(address token, address nftStorage, address to, uint256 id, uint256 amount)
        internal
        returns (bool success)
    {
        uint256 externalBalance = IERC1155(token).balanceOf(nftStorage, id);
        if (externalBalance != 0) {
            bool transferred = tryTransferFromERC1155(token, nftStorage, address(this), id, externalBalance);
            if (!transferred) return false;
        }

        success = tryTransferFromERC1155(token, address(this), to, id, amount);
        if (!success) {
            uint256 internalBalance = IERC1155(token).balanceOf(address(this), id);

            if (internalBalance == 0) {
                return _tryMintERC1155(token, to, id, amount);
            }

            return tryTransferFromERC1155(token, address(this), to, id, internalBalance)
                && _tryMintERC1155(token, to, id, amount - internalBalance);
        }
    }

    /**
     * @dev Transfers ERC1155 token and returns the result.
     */
    function tryTransferFromERC1155(address token, address from, address to, uint256 id, uint256 amount)
        internal
        returns (bool success)
    {
        (success,) = token.call(abi.encodeCall(IERC1155.safeTransferFrom, (from, to, id, amount, new bytes(0))));
    }

    /**
     * @dev Mints ERC1155 token and returns the result.
     */
    function _tryMintERC1155(address token, address to, uint256 id, uint256 amount) private returns (bool success) {
        (success,) = token.call(abi.encodeCall(IERC1155Mintable.mint, (to, id, amount, new bytes(0))));
    }

    function _tryGetOwnerOf(address token, uint256 id) private view returns (address owner) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeCall(IERC721.ownerOf, (id)));
        if (success && data.length == 32) {
            owner = abi.decode(data, (address));
        }
    }
}
