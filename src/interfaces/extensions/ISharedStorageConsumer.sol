// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISharedStorageConsumer {
    event SharedStorageUpdated(
        address indexed sender,
        address indexed sharedStorage,
        bool shouldAdd
    );

    function setSharedStorage(address sharedStorage, bool shouldAdd) external;

    function SHARED_STORAGE_SETTER_ROLE() external view returns (bytes32);

    function isSharedStorage(address sharedStorage) external view returns (bool);
}