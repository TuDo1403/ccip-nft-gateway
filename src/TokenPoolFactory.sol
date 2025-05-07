// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

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
    mapping(uint64 remoteChainSelector => address router) internal s_remoteRouters;
    mapping(Standard std => mapping(PoolType pt => PoolConfig config)) internal s_poolConfigs;

    modifier onlySupported(Standard std, PoolType pt) {
        _requireSupport(std, pt);
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

    function addRemoteFactory(uint64 remoteChainSelector, address factory, address router)
        external
        nonZero(router)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        s_remoteRouters[remoteChainSelector] = router;
        _addRemoteChain(remoteChainSelector, factory);

        emit RemotePoolAdded(msg.sender, remoteChainSelector, factory, router);
    }

    function removeRemoteFactory(uint64 remoteChainSelector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete s_remoteRouters[remoteChainSelector];
        _removeRemoteChain(remoteChainSelector);

        emit RemotePoolRemoved(msg.sender, remoteChainSelector);
    }

    function claimAdminPool(address pool, address token) external {
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
            _predictPool(remote.std, remote.pt, msg.sender, local.chainSelector, remote.chainSelector, remote.token);
        if (remote.pool != actual) revert PredictAddressNotMatch(remote.pool, actual);

        _sendDataPayFeeToken({
            remoteChainSelector: remote.chainSelector,
            receiver: getRemoteFactory(remote.chainSelector),
            feeToken: feeToken,
            gasLimit: s_poolConfigs[remote.std][remote.pt]._deployGas,
            allowOutOfOrderExecution: false,
            data: abi.encode(msg.sender, remote, local)
        });

        _deployPoolAndInit(msg.sender, local.chainSelector, local, remote);
    }

    function updatePoolConfig(
        Standard std,
        PoolType pt,
        uint32 deployGas,
        uint32 fixedGas,
        uint32 dynamicGas,
        address blueprint
    ) external onlySupported(std, pt) onlyRole(DEFAULT_ADMIN_ROLE) nonZero(blueprint) {
        s_poolConfigs[std][pt] =
            PoolConfig({_deployGas: deployGas, _fixedGas: fixedGas, _dynamicGas: dynamicGas, _blueprint: blueprint});

        emit PoolConfigUpdated(msg.sender, std, pt, s_poolConfigs[std][pt]);
    }

    function predictPool(Standard std, PoolType pt, address srcCreator, uint64 dstChainSelector, address token)
        public
        view
        returns (address predicted)
    {
        return _predictPool(std, pt, srcCreator, getCurrentChainSelector(), dstChainSelector, token);
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

    function getDeployConfig(Standard std, PoolType pt, address srcCreator, uint64 dstChainSelector, address token)
        external
        view
        returns (DeployConfig memory config)
    {
        config.std = std;
        config.pt = pt;
        config.pool = _predictPool(std, pt, srcCreator, getCurrentChainSelector(), dstChainSelector, token);
        config.chainSelector = dstChainSelector;
        config.token = (token);
        config.fixedGas = s_poolConfigs[std][pt]._fixedGas;
        config.dynamicGas = s_poolConfigs[std][pt]._dynamicGas;
    }

    function getRemoteFactory(uint64 remoteChainSelector)
        public
        view
        onlyEnabledChain(remoteChainSelector)
        returns (address)
    {
        return _getRemoteSender(remoteChainSelector);
    }

    function getRemoteRouter(uint64 remoteChainSelector) public view returns (address) {
        return s_remoteRouters[remoteChainSelector];
    }

    function estimateFee(address feeToken, Standard std, PoolType pt, uint64 remoteChainSelector)
        external
        view
        onlySupported(std, pt)
        returns (uint256 fee)
    {
        DeployConfig memory empty;
        (fee,) = _getSendDataFee({
            remoteChainSelector: remoteChainSelector,
            receiver: (getRemoteFactory(remoteChainSelector)),
            feeToken: feeToken,
            gasLimit: s_poolConfigs[std][pt]._deployGas,
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
        assert(message.sourceChainSelector == remote.chainSelector);

        _deployPoolAndInit(srcCreator, message.sourceChainSelector, local, remote);
    }

    function _deployPoolAndInit(
        address srcCreator,
        uint64 srcChainSelector,
        DeployConfig memory local,
        DeployConfig memory remote
    ) internal onlyLocalChain(local.chainSelector) whenNotPaused {
        address localPool = local.pool;
        bytes32 salt = _getSalt(local.std, local.pt, srcCreator, srcChainSelector, local.token);

        address actual = s_poolConfigs[local.std][local.pt]._blueprint.cloneDeterministic(salt);
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
        Standard std,
        PoolType pt,
        address srcCreator,
        uint64 srcChainSelector,
        uint64 dstChainSelector,
        address token
    ) internal view nonZero(srcCreator) returns (address predicted) {
        _requireNonZero(srcChainSelector);
        address deployer =
            dstChainSelector == getCurrentChainSelector() ? address(this) : getRemoteFactory(dstChainSelector);
        address blueprint = s_poolConfigs[std][pt]._blueprint;
        predicted = Clones.predictDeterministicAddress(
            blueprint, _getSalt(std, pt, srcCreator, srcChainSelector, token), deployer
        );
    }

    function _getSalt(Standard std, PoolType pt, address srcCreator, uint64 srcChainSelector, address token)
        internal
        pure
        nonZero(token)
        onlySupported(std, pt)
        returns (bytes32 salt)
    {
        salt = keccak256(abi.encode(std, pt, srcCreator, srcChainSelector, token));
    }

    function _requireSupport(Standard std, PoolType pt) internal pure {
        if (std == Standard.Unknown) revert StandardNotSupported(std);
        if (pt == PoolType.Unknown) revert PoolTypeNotSupported(pt);
    }
}
