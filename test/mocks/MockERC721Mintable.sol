// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MockERC721} from "forge-std/mocks/MockERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC721Mintable is MockERC721, Ownable {
    mapping(address => bool) public canMint;
    bool public allowAll;

    constructor(string memory _name, string memory _symbol) Ownable(msg.sender) {
        allowAll = true;
        initialize(_name, _symbol);
    }

    function setAllowAll(bool allow) external {
        allowAll = allow;
    }

    function setCanMint(address minter, bool canMint_) external {
        canMint[minter] = canMint_;
    }

    function mint(address to, uint256 tokenId) external {
        require(canMint[msg.sender] || allowAll, "Not allowed to mint");
        _mint(to, tokenId);
    }

    function mintBatch(address to, uint256[] calldata tokenIds) external {
        require(canMint[msg.sender] || allowAll, "Not allowed to mint");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _mint(to, tokenIds[i]);
        }
    }
}
