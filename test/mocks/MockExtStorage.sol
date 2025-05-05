// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IExtStorage} from "src/interfaces/external/IExtStorage.sol";
import {IERC721Mintable} from "src/interfaces/external/IERC721Mintable.sol";

contract MockExtStorage is IExtStorage {
    function setApprovalForAll(address nft, address operator, bool approved) external {
        IERC721Mintable(nft).setApprovalForAll(operator, approved);
    }

    function mintFor(address nft, address to, uint256 tokenId) external {
        IERC721Mintable(nft).mint(to, tokenId);
    }
}
