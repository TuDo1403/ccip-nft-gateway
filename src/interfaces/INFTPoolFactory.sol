// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface INFTPoolFactory {
    error PredictAddressNotMatch(address expected, address actual);
    error PoolTypeNotSupported(PoolType poolType);
    error StandardNotSupported(Standard standard);
    error FactoryAlreadyAdded(uint64 chainSelector, address pool);

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
        address _bluePrint;
    }

    struct DeployConfig {
        Standard std;
        PoolType pt;
        address pool;
        address token;
        uint32 fixedGas;
        uint32 dynamicGas;
        uint64 chainSelector;
    }

    event NonceIncremented(address indexed by, uint64 indexed chainSelector, address indexed creator, uint256 nonce);
    event PoolConfigUpdated(address indexed by, Standard indexed std, PoolType indexed, PoolConfig config);
    event RemotePoolAdded(address indexed by, uint64 indexed chainSelector, address indexed pool, address router);
    event RemotePoolRemoved(address indexed by, uint64 indexed chainSelector);
}
