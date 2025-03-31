// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IERC1155Mintable is IERC1155 {
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external;
}
