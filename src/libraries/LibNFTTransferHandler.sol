// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
// import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
// import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

// import {IERC1155Mintable} from "src/interfaces/ext/IERC1155Mintable.sol";
// import {IERC721Mintable} from "src/interfaces/ext/IERC721Mintable.sol";

// library LibNFTTransferHandler {
//     using ERC165Checker for address;

//     /**
//      *      TRANSFER ERC-721
//      */

//     /**
//      * @dev Transfers the ERC721 token out. If the transfer failed, mints the ERC721.
//      * @return success Returns `false` if both transfer and mint are failed.
//      */
//     function tryTransferOutOrMintERC721(address extStorage, address token, address to, uint256 id)
//         internal
//         returns (bool success)
//     {
//         address owner = _tryGetOwnerOf(token, id);
//         if (owner != address(0)) {
//             return tryTransferFromERC721(token, owner, to, id);
//         } else {
//             return tryMintERC721FromExtStorage(token, to, id);
//         }
//     }

//     /**
//      * @dev Transfers ERC721 token and returns the result.
//      */
//     function tryTransferFromERC721(address token, address from, address to, uint256 id)
//         internal
//         returns (bool success)
//     {
//         (success,) = token.call(abi.encodeCall(IERC721.transferFrom, (from, to, id)));
//     }

//     /**
//      * @dev Mints ERC721 token and returns the result.
//      */
//     function tryMintERC721FromExtStorage(address extStorage, address token, address to, uint256 id)
//         private
//         returns (bool success)
//     {
//         (success,) = extStorage.call(abi.encodeCall(IERC721Mintable.mint, (token, to, id)));
//     }

//     function _tryGetOwnerOf(address token, uint256 id) private view returns (address owner) {
//         (bool success, bytes memory data) = token.staticcall(abi.encodeCall(IERC721.ownerOf, (id)));
//         if (success && data.length == 32) {
//             owner = abi.decode(data, (address));
//         }
//     }
// }
