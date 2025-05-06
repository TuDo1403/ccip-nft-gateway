// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

interface ILockMintERC721TokenPool {
    error LengthMismatch(uint256 expected, uint256 actual);
    error MintFailed(address minter, address to, uint256 id);
    error ExtStorageAlreadyAdded(address extStorage);
    error ExtStorageNotAdded(address extStorage);
    error ERC721TransferFailed(address recipient, uint256 id);

    event ExternalStorageUpdated(address indexed by, address indexed extStorage, bool added);

    function updateExternalStorage(address extStorage, bool shouldAdd) external;

    event CrossTransfer(
        Any2EVMAddress srcFrom,
        address indexed dstTo,
        bytes32 indexed messageId,
        uint256[] ids,
        uint64 srcChainSelector,
        uint64 dstChainSelector
    );
}
