// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface INFTPoolFactory {
    error PredictAddressNotMatch(address expected, address actual);
    error PoolTypeNotSupported(PoolType poolType);
    error InvalidTransferLimitPerRequest();
    error CurrentChainSelectorNotMatch(uint64 currentChainSelector);
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

    struct RemoteFactoryConfig {
        address _factory;
        address _router;
    }

    struct DeployConfig {
        Standard std;
        PoolType pt;
        address pool;
        address token;
        uint64 chainSelector;
    }
}
