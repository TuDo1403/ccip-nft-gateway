// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {CCIPSenderReceiverUpgradeable} from "src/extensions/CCIPSenderReceiverUpgradeable.sol";
import {IOwnable} from "src/interfaces/external/IOwnable.sol";
import {IERC721TokenPool} from "src/interfaces/IERC721TokenPool.sol";
import {INFTPoolFactory} from "src/interfaces/INFTPoolFactory.sol";
import {INFTPoolCallback} from "src/interfaces/INFTPoolCallback.sol";

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
    EnumerableSet.UintSet internal s_remoteChainSelectors;
    // mapping(address creator => uint256 nonce) internal s_creatorNonces;
    mapping(uint64 remoteChainSelector => address factory) internal s_remoteFactories;
    mapping(Standard std => mapping(PoolType pt => PoolConfig config)) internal s_poolConfigs;
    mapping(uint64 chainSelector => mapping(address creator => uint256 nonce)) internal s_creatorNonces;

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address router, address rmnProxy, uint64 currentChainSelector)
        external
        initializer
    {
        __CCIPSenderReceiverUpgradeable_init(router, rmnProxy, currentChainSelector);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function updatePoolConfig(Standard std, PoolType poolType, uint64 fixedGas, uint64 dynamicGas, address bluePrint)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        s_poolConfigs[std][poolType] = PoolConfig({fixedGas: fixedGas, dynamicGas: dynamicGas, bluePrint: bluePrint});
    }

    function _getSalt(Standard std, PoolType pt, address creator, uint64 chainSelector)
        internal
        view
        returns (bytes32 salt)
    {
        return keccak256(abi.encode(std, pt, creator, chainSelector, s_creatorNonces[chainSelector][creator]));
    }

    function predictPool(Standard std, PoolType pt, address creator, uint64 chainSelector)
        public
        view
        returns (address)
    {
        address deployer =
            chainSelector == s_currentChainSelector ? address(this) : s_remoteFactories[chainSelector]._factory;
        address bluePrint = s_poolConfigs[std][pt].bluePrint;
        return Clones.predictDeterministicAddress(bluePrint, _getSalt(std, pt, creator, chainSelector), deployer);
    }

    function getFee(IERC20 feeToken, Standard std, PoolType pt, uint64 remoteChainSelector)
        external
        view
        onlyOtherChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
        returns (uint256 fee)
    {
        DeployConfig memory empty;
        (fee,) = _getSendDataFee({
            destChainSelector: remoteChainSelector,
            receiver: s_remoteFactories[remoteChainSelector],
            feeToken: feeToken,
            gasLimit: s_poolConfigs[std][pt].deployGas,
            allowOutOfOrderExecution: false,
            data: abi.encode(uint8(0), bytes32(0), address(0), empty, empty)
        });
    }

    function deployPool(
        IERC20 feeToken,
        bool crossDeploy,
        DeployConfig calldata local,
        DeployConfig calldata remote
    )
        external
        whenNotPaused
        nonZero(local.token)
        onlyOtherChain(remote.chainSelector)
        onlyEnabledChain(remote.chainSelector)
    {
        if (local.chainSelector != s_currentChainSelector) revert CurrentChainSelectorNotMatch(local.chainSelector);

        if (crossDeploy) {
            address remoteDeployer = s_remoteFactories[remote.chainSelector]._factory;
            address actual = predictPool(remote.std, remote.pt, remoteDeployer, local.chainSelector);
            if (remote.pool != actual) revert PredictAddressNotMatch(remote.pool, actual);
            _incrementNonce(local.chainSelector, remoteDeployer);

            _sendDataPayFeeToken({
                destChainSelector: remote.chainSelector,
                receiver: s_remoteFactories[remote.chainSelector],
                feeToken: feeToken,
                gasLimit: s_poolConfigs[remote.std][remote.pt].deployGas,
                allowOutOfOrderExecution: false,
                data: abi.encode(remote, local)
            });
        }

        _deployPoolAndInit(local.chainSelector, local, remote);
    }

    function addRemoteFactory(uint64 remoteChainSelector, address factory)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonZero(factory)
        onlyOtherChain(remoteChainSelector)
    {
        if (s_remoteFactories[remoteChainSelector] != address(0)) {
            revert FactoryAlreadyAdded(remoteChainSelector, factory);
        }
        s_remoteFactories[remoteChainSelector] = factory;
        s_remoteChainSelectors.add(remoteChainSelector);
    }

    function removeRemoteFactory(uint64 remoteChainSelector)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        onlyOtherChain(remoteChainSelector)
        onlyEnabledChain(remoteChainSelector)
    {
        s_remoteFactories[remoteChainSelector] = address(0);
        s_remoteChainSelectors.remove(remoteChainSelector);
    }

    function isSupportedChain(uint64 remoteChainSelector) public view override returns (bool) {
        return s_remoteFactories[remoteChainSelector] != address(0);
    }

    function isSenderEnabled(uint64 remoteChainSelector, address srcSender) public view override returns (bool) {
        return s_remoteFactories[remoteChainSelector] == srcSender;
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
        s_creatorNonces[chainSelector][creator]++;
    }

    function _ccipReceive(Client.Any2EVMMessage calldata message) internal virtual override whenNotPaused {
        (DeployConfig memory local, DeployConfig memory remote) = abi.decode(message.data, (DeployConfig, DeployConfig));
        _deployPoolAndInit(message.sourceChainSelector, local, remote);
    }

    function _deployPoolAndInit(address srcChainSelector, DeployConfig memory local, DeployConfig memory remote)
        internal
    {
        bytes32 salt = _getSalt(local.std, local.pt, msg.sender, srcChainSelector);
        address actual = s_poolConfigs[local.std][local.pt].bluePrint.cloneDeterministic(salt);
        if (local.pool != actual) revert PredictAddressNotMatch(local.pool, actual);
        _incrementNonce(srcChainSelector, msg.sender);

        // Initialize the localPool
        INFTPoolCallback(local.pool).initialize(
            address(this),
            address(s_router),
            address(s_rmnProxy),
            local.token,
            local.chainSelector,
            local.dynamicGas,
            local.fixedGas
        );
        if (remote.pool != address(0)) {
            INFTPoolCallback(local.pool).addRemotePool(remote.chainSelector, remote.pool, remote.token);
        }
    }
}
