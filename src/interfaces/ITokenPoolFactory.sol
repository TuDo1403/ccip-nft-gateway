// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

interface ITokenPoolFactory {
    error Unauthorized(address sender);
    error NotTokenPool(address pool);
    error PredictAddressNotMatch(address expected, address actual);
    error PoolTypeNotSupported(PoolType poolType);
    error StandardNotSupported(Standard standard);
    error FactoryAlreadyAdded(uint64 chainSelector, address pool);
    error AlreadyClaimedAdmin(address pool, address sender);

    enum PoolType {
        Unknown,
        LockMint
    }

    enum Standard {
        Unknown,
        ERC721,
        ERC1155
    }

    struct PoolConfig {
        uint32 _deployGas;
        uint32 _fixedGas;
        uint32 _dynamicGas;
        address _blueprint;
    }

    struct DeployConfig {
        Standard std;
        PoolType pt;
        Any2EVMAddress pool;
        Any2EVMAddress token;
        uint32 fixedGas;
        uint32 dynamicGas;
        uint64 chainSelector;
    }

    event NonceIncremented(address indexed by, uint64 indexed chainSelector, address indexed creator, uint256 nonce);
    event PoolConfigUpdated(address indexed by, Standard indexed std, PoolType indexed, PoolConfig config);
    event RemotePoolAdded(address indexed by, uint64 indexed chainSelector, address indexed pool, address router);
    event RemotePoolRemoved(address indexed by, uint64 indexed chainSelector);
    event PoolDeployed(address indexed by, address indexed pool, uint64 indexed srcChainSelector, bytes32 salt);
}
