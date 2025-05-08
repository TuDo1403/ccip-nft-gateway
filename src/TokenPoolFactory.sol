// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ITypeAndVersion} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {ITokenAdminRegistryExtended} from "src/interfaces/external/ITokenAdminRegistryExtended.sol";
import {CCIPSenderReceiverUpgradeable} from "src/extensions/CCIPSenderReceiverUpgradeable.sol";
import {ITokenPoolFactory} from "src/interfaces/ITokenPoolFactory.sol";
import {ITokenPoolCallback} from "src/interfaces/pools/ITokenPoolCallback.sol";

contract TokenPoolFactory is
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    CCIPSenderReceiverUpgradeable,
    ITokenPoolFactory
{
    using Clones for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Reserved slots for upgradeability
    uint256[50] private __gap;

    ITokenAdminRegistryExtended internal s_tokenAdminRegistry;
    EnumerableSet.AddressSet internal s_deployedPools;
    EnumerableSet.AddressSet internal s_blueprints;
    mapping(address blueprint => PoolConfig config) internal s_blueprintConfigs;

    modifier onlySupported(address blueprint) {
        _requireSupport(blueprint);
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address tokenAdminRegistry, address router, uint64 currentChainSelector)
        external
        nonZero(admin)
        nonZero(tokenAdminRegistry)
        initializer
    {
        s_tokenAdminRegistry = ITokenAdminRegistryExtended(tokenAdminRegistry);
        __CCIPSenderReceiver_init(router, currentChainSelector);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function addRemoteFactory(uint64 remoteChainSelector, address factory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addRemoteChain(remoteChainSelector, factory);
        emit RemoteFactoryAdded(msg.sender, remoteChainSelector, factory);
    }

    function removeRemoteFactory(uint64 remoteChainSelector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeRemoteChain(remoteChainSelector);
        emit RemoteFactoryRemoved(msg.sender, remoteChainSelector);
    }

    function addBlueprint(address blueprint, uint32 deployGas, uint32 fixedGas, uint32 dynamicGas)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonZero(blueprint)
    {
        _requireNonZero(deployGas);
        _requireNonZero(fixedGas);
        _requireNonZero(dynamicGas);

        if (!s_blueprints.add(blueprint)) revert BlueprintAlreadyAdded(blueprint);

        PoolConfig memory config = PoolConfig({_deployGas: deployGas, _fixedGas: fixedGas, _dynamicGas: dynamicGas});
        s_blueprintConfigs[blueprint] = config;

        emit BlueprintAdded(msg.sender, blueprint, config, ITypeAndVersion(blueprint).typeAndVersion());
    }

    function removeBlueprint(address blueprint) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!s_blueprints.remove(blueprint)) revert BlueprintNotAdded(blueprint);
        delete s_blueprintConfigs[blueprint];
        emit BlueprintRemoved(msg.sender, blueprint);
    }

    function claimAdminPool(address pool, address token) external whenNotPaused {
        if (!s_deployedPools.contains(pool)) revert NotTokenPool(pool);
        if (!ITokenPoolCallback(pool).isSupportedToken(token)) revert Unauthorized(msg.sender);
        ITokenAdminRegistryExtended.TokenConfig memory config = s_tokenAdminRegistry.getTokenConfig(token);
        if (config.administrator != msg.sender) revert Unauthorized(msg.sender);
        if (config.tokenPool != pool) revert NotTokenPool(pool);
        if (!ITokenPoolCallback(pool).hasRole(DEFAULT_ADMIN_ROLE, address(this))) {
            revert AlreadyClaimedAdmin(pool, msg.sender);
        }

        ITokenPoolCallback(pool).grantRole(ITokenPoolCallback(pool).DEFAULT_ADMIN_ROLE(), msg.sender);

        // give up all roles
        ITokenPoolCallback(pool).renounceRole(ITokenPoolCallback(pool).SHARED_STORAGE_SETTER_ROLE(), address(this));
        ITokenPoolCallback(pool).renounceRole(ITokenPoolCallback(pool).TOKEN_POOL_OWNER_ROLE(), address(this));
        ITokenPoolCallback(pool).renounceRole(ITokenPoolCallback(pool).RATE_LIMITER_ROLE(), address(this));
        ITokenPoolCallback(pool).renounceRole(ITokenPoolCallback(pool).DEFAULT_ADMIN_ROLE(), address(this));
        // intentionally not renouncing the PAUSER_ROLE
        // ITokenPoolCallback(pool).renounceRole(ITokenPoolCallback(pool).PAUSER_ROLE(), address(this));
    }

    function deployPool(DeployConfig calldata local, DeployConfig calldata remote) external {
        _deployPoolAndInit(msg.sender, local.chainSelector, local, remote);
    }

    function dualDeployPool(address feeToken, DeployConfig calldata local, DeployConfig calldata remote)
        external
        payable
    {
        address actual =
            _predictPool(remote.blueprint, msg.sender, local.chainSelector, remote.chainSelector, remote.token);
        if (remote.pool != actual) revert PredictAddressNotMatch(remote.pool, actual);

        _sendDataPayFeeToken({
            remoteChainSelector: remote.chainSelector,
            receiver: getRemoteFactory(remote.chainSelector),
            feeToken: feeToken,
            gasLimit: s_blueprintConfigs[remote.blueprint]._deployGas,
            allowOutOfOrderExecution: false,
            data: abi.encode(msg.sender, remote, local)
        });

        _deployPoolAndInit(msg.sender, local.chainSelector, local, remote);
    }

    function predictPool(address blueprint, address srcCreator, uint64 dstChainSelector, address token)
        public
        view
        returns (address predicted)
    {
        return _predictPool(blueprint, srcCreator, getCurrentChainSelector(), dstChainSelector, token);
    }

    function getDeployedPools(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory pools, uint256 total)
    {
        total = s_deployedPools.length();
        if (offset >= total) return (pools, total);
        if (limit == 0) limit = total - offset;
        if (limit > total) limit = total;

        pools = new address[](limit);
        for (uint256 i = 0; i < limit; ++i) {
            pools[i] = s_deployedPools.at(offset + i);
        }
    }

    function isSupportedBlueprint(address blueprint) public view returns (bool) {
        return s_blueprints.contains(blueprint);
    }

    function getSupportedBlueprints()
        external
        view
        returns (address[] memory blueprints, string[] memory typesAndVersions)
    {
        blueprints = s_blueprints.values();
        uint256 length = blueprints.length;

        typesAndVersions = new string[](length);
        for (uint256 i; i < length; ++i) {
            typesAndVersions[i] = ITypeAndVersion(blueprints[i]).typeAndVersion();
        }
    }

    function getDeployConfig(address blueprint, address srcCreator, uint64 dstChainSelector, address token)
        external
        view
        returns (DeployConfig memory config)
    {
        config.blueprint = blueprint;
        config.pool = _predictPool(blueprint, srcCreator, getCurrentChainSelector(), dstChainSelector, token);
        config.chainSelector = dstChainSelector;
        config.token = token;
        config.fixedGas = s_blueprintConfigs[blueprint]._fixedGas;
        config.dynamicGas = s_blueprintConfigs[blueprint]._dynamicGas;
    }

    function getRemoteFactory(uint64 remoteChainSelector)
        public
        view
        onlyEnabledChain(remoteChainSelector)
        returns (address)
    {
        return _getRemoteSender(remoteChainSelector);
    }

    function estimateFee(address feeToken, address blueprint, uint64 remoteChainSelector)
        external
        view
        onlySupported(blueprint)
        returns (uint256 fee)
    {
        DeployConfig memory empty;
        (fee,) = _getSendDataFee({
            remoteChainSelector: remoteChainSelector,
            receiver: getRemoteFactory(remoteChainSelector),
            feeToken: feeToken,
            gasLimit: s_blueprintConfigs[blueprint]._deployGas,
            allowOutOfOrderExecution: false,
            data: abi.encode(empty, empty)
        });
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerableUpgradeable, CCIPSenderReceiverUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _ccipReceive(Client.Any2EVMMessage calldata message) internal virtual override whenNotPaused {
        (address srcCreator, DeployConfig memory local, DeployConfig memory remote) =
            abi.decode(message.data, (address, DeployConfig, DeployConfig));
        if (message.sourceChainSelector != remote.chainSelector) {
            revert RemoteChainNotMatch(message.sourceChainSelector, remote.chainSelector);
        }

        _deployPoolAndInit(srcCreator, message.sourceChainSelector, local, remote);
    }

    function _deployPoolAndInit(
        address srcCreator,
        uint64 srcChainSelector,
        DeployConfig memory local,
        DeployConfig memory remote
    ) internal onlyLocalChain(local.chainSelector) whenNotPaused onlySupported(local.blueprint) {
        address localPool = local.pool;
        bytes32 salt = _getSalt(srcCreator, srcChainSelector, local.token);

        address actual = local.blueprint.cloneDeterministic(salt);
        if (localPool != actual) revert PredictAddressNotMatch(localPool, actual);

        ITokenPoolCallback(localPool).initialize({
            admin: address(this),
            fixedGas: local.fixedGas,
            dynamicGas: local.dynamicGas,
            router: address(getRouter()),
            currentChainSelector: local.chainSelector
        });

        if (remote.pool != address(0)) {
            ITokenPoolCallback(localPool).addRemotePool(remote.chainSelector, remote.pool);
        }
        if (local.token != address(0)) {
            ITokenPoolCallback(localPool).mapRemoteToken(local.token, remote.chainSelector, remote.token);
        }

        ITokenPoolCallback(localPool).grantRole(ITokenPoolCallback(localPool).SHARED_STORAGE_SETTER_ROLE(), srcCreator);
        ITokenPoolCallback(localPool).grantRole(ITokenPoolCallback(localPool).TOKEN_POOL_OWNER_ROLE(), srcCreator);
        ITokenPoolCallback(localPool).grantRole(ITokenPoolCallback(localPool).RATE_LIMITER_ROLE(), srcCreator);
        ITokenPoolCallback(localPool).grantRole(ITokenPoolCallback(localPool).PAUSER_ROLE(), srcCreator);

        s_deployedPools.add(localPool);

        emit PoolDeployed(srcCreator, localPool, srcChainSelector, salt);
    }

    function _predictPool(
        address blueprint,
        address srcCreator,
        uint64 srcChainSelector,
        uint64 dstChainSelector,
        address token
    ) internal view nonZero(srcCreator) onlySupported(blueprint) returns (address predicted) {
        address deployer =
            dstChainSelector == getCurrentChainSelector() ? address(this) : getRemoteFactory(dstChainSelector);
        predicted = blueprint.predictDeterministicAddress(_getSalt(srcCreator, srcChainSelector, token), deployer);
    }

    function _getSalt(address srcCreator, uint64 srcChainSelector, address token)
        internal
        pure
        nonZero(token)
        nonZero(srcCreator)
        returns (bytes32 salt)
    {
        _requireNonZero(srcChainSelector);
        salt = keccak256(abi.encode(srcCreator, srcChainSelector, token));
    }

    function _requireSupport(address blueprint) internal view {
        if (!isSupportedBlueprint(blueprint)) revert BlueprintNotSupported(blueprint);
    }
}
