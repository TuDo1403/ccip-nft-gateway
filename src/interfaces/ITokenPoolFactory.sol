// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ITokenPoolFactory {
    error Unauthorized(address sender);
    error NotTokenPool(address pool);
    error PredictAddressNotMatch(address expected, address actual);
    error BlueprintNotSupported(address blueprint);
    error BlueprintNotAdded(address blueprint);
    error BlueprintAlreadyAdded(address blueprint);
    error FactoryAlreadyAdded(uint64 chainSelector, address pool);
    error AlreadyClaimedAdmin(address pool, address sender);
    error RemoteChainNotMatch(uint64 expected, uint64 actual);

    struct PoolConfig {
        uint32 _deployGas;
        uint32 _fixedGas;
        uint32 _dynamicGas;
    }

    struct DeployConfig {
        address blueprint;
        address pool;
        address token;
        uint32 fixedGas;
        uint32 dynamicGas;
        uint64 chainSelector;
    }

    event BlueprintRemoved(address indexed by, address indexed blueprint);
    event BlueprintAdded(address indexed by, address indexed blueprint, PoolConfig config, string typeAndVersion);
    event RemoteFactoryAdded(address indexed by, uint64 indexed chainSelector, address indexed pool);
    event RemoteFactoryRemoved(address indexed by, uint64 indexed chainSelector);
    event PoolDeployed(address indexed by, address indexed pool, uint64 indexed srcChainSelector, bytes32 salt);
}
