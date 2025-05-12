// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {ISharedStorageConsumer} from "src/interfaces/extensions/ISharedStorageConsumer.sol";

abstract contract SharedStorageConsumerUpgradeable is AccessControlEnumerableUpgradeable, ISharedStorageConsumer {
    bytes32 public constant SHARED_STORAGE_SETTER_ROLE = keccak256("SHARED_STORAGE_SETTER_ROLE");

    /// @dev Gap for future upgrades
    uint256[50] private __gap1;

    mapping(address => bool) private s_sharedStorage;

    /// @dev Gap for future upgrades
    uint256[50] private __gap2;

    function __SharedStorageConsumer_init(address sharedStorageSetter) internal onlyInitializing {
        __SharedStorageConsumer_init_unchained(sharedStorageSetter);
    }

    function __SharedStorageConsumer_init_unchained(address sharedStorageSetter) internal onlyInitializing {
        _grantRole(SHARED_STORAGE_SETTER_ROLE, sharedStorageSetter);
    }

    function setSharedStorage(address sharedStorage, bool shouldAdd) external onlyRole(SHARED_STORAGE_SETTER_ROLE) {
        s_sharedStorage[sharedStorage] = shouldAdd;
        emit SharedStorageUpdated(msg.sender, sharedStorage, shouldAdd);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ISharedStorageConsumer).interfaceId || super.supportsInterface(interfaceId);
    }

    function isSharedStorage(address sharedStorage) public view returns (bool yes) {
        return s_sharedStorage[sharedStorage];
    }
}
