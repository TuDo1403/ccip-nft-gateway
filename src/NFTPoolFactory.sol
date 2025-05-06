// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {CCIPSenderReceiverUpgradeable} from "src/extensions/CCIPSenderReceiverUpgradeable.sol";
import {INFTPoolFactory} from "src/interfaces/INFTPoolFactory.sol";
import {ITokenPoolCallback} from "src/interfaces/pools/ITokenPoolCallback.sol";

contract NFTPoolFactory is
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    CCIPSenderReceiverUpgradeable,
    INFTPoolFactory
{
    using Clones for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Reserved slots for upgradeability
    uint256[50] private __gap;

    EnumerableSet.AddressSet internal s_deployedPools;
    mapping(uint64 remoteChainSelector => address router) internal s_remoteRouters;
    mapping(Standard std => mapping(PoolType pt => PoolConfig config)) internal s_poolConfigs;
    mapping(uint64 chainSelector => mapping(address creator => uint256 nonce)) internal s_creatorNonces;

    modifier onlySupported(Standard std, PoolType pt) {
        _requireSupport(std, pt);
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address router, address rmnProxy, uint64 currentChainSelector)
        external
        nonZero(admin)
        initializer
    {
        __CCIPSenderReceiverUpgradeable_init(router, rmnProxy, currentChainSelector);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function addRemoteFactory(uint64 remoteChainSelector, address factory, address router)
        external
        nonZero(router)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        s_remoteRouters[remoteChainSelector] = router;
        _addRemoteChain(remoteChainSelector, abi.encode(factory));

        emit RemotePoolAdded(msg.sender, remoteChainSelector, factory, router);
    }

    function removeRemoteFactory(uint64 remoteChainSelector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete s_remoteRouters[remoteChainSelector];
        _removeRemoteChain(remoteChainSelector);

        emit RemotePoolRemoved(msg.sender, remoteChainSelector);
    }

    function deployPool(DeployConfig calldata local, DeployConfig calldata remote)
        external
        onlySupported(local.std, local.pt)
        whenNotPaused
    {
        _deployPoolAndInit(local.chainSelector, local, remote);
    }

    function dualDeployPool(IERC20 feeToken, DeployConfig calldata local, DeployConfig calldata remote)
        external
        onlySupported(local.std, local.pt)
        onlySupported(remote.std, remote.pt)
        whenNotPaused
    {
        address remoteDeployer = getRemoteRouter(remote.chainSelector);
        address actual = predictPool(remote.std, remote.pt, remoteDeployer, remote.chainSelector);
        if (remote.pool != actual) revert PredictAddressNotMatch(remote.pool, actual);
        _incrementNonce(local.chainSelector, remoteDeployer);

        _sendDataPayFeeToken({
            remoteChainSelector: remote.chainSelector,
            receiver: getRemoteFactory(remote.chainSelector),
            feeToken: feeToken,
            gasLimit: s_poolConfigs[remote.std][remote.pt]._deployGas,
            allowOutOfOrderExecution: false,
            data: abi.encode(remote, local)
        });

        _deployPoolAndInit(local.chainSelector, local, remote);
    }

    function updatePoolConfig(
        Standard std,
        PoolType pt,
        uint32 deployGas,
        uint32 fixedGas,
        uint32 dynamicGas,
        address bluePrint
    ) external onlySupported(std, pt) onlyRole(DEFAULT_ADMIN_ROLE) nonZero(bluePrint) {
        s_poolConfigs[std][pt] =
            PoolConfig({_deployGas: deployGas, _fixedGas: fixedGas, _dynamicGas: dynamicGas, _bluePrint: bluePrint});

        emit PoolConfigUpdated(msg.sender, std, pt, s_poolConfigs[std][pt]);
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

    function getRemoteFactory(uint64 remoteChainSelector) public view returns (address) {
        return abi.decode(s_remoteChainConfigs[remoteChainSelector]._addr, (address));
    }

    function getRemoteRouter(uint64 remoteChainSelector) public view returns (address) {
        return s_remoteRouters[remoteChainSelector];
    }

    function predictPool(Standard std, PoolType pt, address creator, uint64 chainSelector)
        public
        view
        onlySupported(std, pt)
        nonZero(creator)
        returns (address)
    {
        _requireNonZero(chainSelector);
        creator = chainSelector == s_currentChainSelector ? creator : getRemoteRouter(chainSelector);
        address deployer = chainSelector == s_currentChainSelector ? address(this) : getRemoteFactory(chainSelector);
        address bluePrint = s_poolConfigs[std][pt]._bluePrint;
        return Clones.predictDeterministicAddress(bluePrint, _getSalt(std, pt, creator, chainSelector), deployer);
    }

    function estimateFee(IERC20 feeToken, Standard std, PoolType pt, uint64 remoteChainSelector)
        external
        view
        onlySupported(std, pt)
        returns (uint256 fee)
    {
        DeployConfig memory empty;
        (fee,) = _getSendDataFee({
            remoteChainSelector: remoteChainSelector,
            receiver: getRemoteFactory(remoteChainSelector),
            feeToken: feeToken,
            gasLimit: s_poolConfigs[std][pt]._deployGas,
            allowOutOfOrderExecution: false,
            data: abi.encode(uint8(0), bytes32(0), address(0), empty, empty)
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

    function _incrementNonce(uint64 chainSelector, address creator) internal {
        uint256 next = ++s_creatorNonces[chainSelector][creator];
        emit NonceIncremented(msg.sender, chainSelector, creator, next);
    }

    function _ccipReceive(Client.Any2EVMMessage calldata message) internal virtual override whenNotPaused {
        (DeployConfig memory local, DeployConfig memory remote) = abi.decode(message.data, (DeployConfig, DeployConfig));
        _deployPoolAndInit(remote.chainSelector, local, remote);
    }

    function _deployPoolAndInit(uint64 srcChainSelector, DeployConfig memory local, DeployConfig memory remote)
        internal
        nonZero(local.token)
        onlyLocalChain(local.chainSelector)
    {
        bytes32 salt = _getSalt(local.std, local.pt, msg.sender, srcChainSelector);
        address actual = s_poolConfigs[local.std][local.pt]._bluePrint.cloneDeterministic(salt);
        if (local.pool != actual) revert PredictAddressNotMatch(local.pool, actual);
        _incrementNonce(srcChainSelector, msg.sender);

        // Initialize the localPool
        ITokenPoolCallback(local.pool).initialize({
            admin: address(this),
            token: local.token,
            fixedGas: local.fixedGas,
            dynamicGas: local.dynamicGas,
            router: address(s_router),
            rmnProxy: address(s_rmnProxy),
            currentChainSelector: local.chainSelector
        });
        if (remote.pool != address(0)) {
            _requireRemoteChain(remote.chainSelector);
            _requireEnabledChain(remote.chainSelector);
            ITokenPoolCallback(local.pool).addRemotePool(remote.chainSelector, remote.pool, remote.token);
        }

        s_deployedPools.add(local.pool);
    }

    function _getSalt(Standard std, PoolType pt, address creator, uint64 chainSelector)
        internal
        view
        returns (bytes32 salt)
    {
        return keccak256(abi.encode(std, pt, creator, chainSelector, s_creatorNonces[chainSelector][creator]));
    }

    function _requireSupport(Standard std, PoolType pt) internal pure {
        if (std == Standard.Unknown) revert StandardNotSupported(std);
        if (pt == PoolType.Unknown) revert PoolTypeNotSupported(pt);
    }
}
