// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {CCIPCrossChainSenderReceiver} from "src/extensions/CCIPCrossChainSenderReceiver.sol";
import {IOwnable} from "src/interfaces/ext/IOwnable.sol";
import {IERC721TokenPool} from "src/interfaces/IERC721TokenPool.sol";

contract NFTPoolFactory is CCIPCrossChainSenderReceiver, Pausable, AccessControlEnumerable {
    using Clones for address;
    using EnumerableSet for EnumerableSet.UintSet;

    error PredictAddressNotMatch(address expected, address actual);
    error PoolTypeNotSupported(PoolType poolType);
    error InvalidTransferLimitPerRequest();
    error CurrentChainSelectorNotMatch(uint64 currentChainSelector);
    error FactoryAlreadyAdded(uint64 chainSelector, address pool);

    enum PoolType {
        ERC721
    }

    struct DeployConfig {
        address pool;
        address token;
        uint64 chainSelector;
        uint16 limitTransferPerRequest;
    }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256[50] private __gap;

    uint64 internal s_deployGasLimit;
    uint64 internal s_defaultFixedGas;
    uint64 internal s_defaultDynamicGas;
    address internal s_erc721PoolBeaconProxy;
    IBeacon internal s_erc721PoolUpgradeableBeacon;
    EnumerableSet.UintSet internal s_remoteChainSelectors;
    mapping(uint64 remoteChainSelector => address factory) internal s_remoteFactories;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address pauser,
        address router,
        uint64 currentChainSelector,
        uint64 deployGasLimit,
        uint64 defaultFixedGas,
        uint64 defaultDynamicGas
    ) external initializer {
        __CCIPCrossChainSenderReceiver_init(router, currentChainSelector);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);

        s_deployGasLimit = deployGasLimit;
        s_defaultFixedGas = defaultFixedGas;
        s_defaultDynamicGas = defaultDynamicGas;
    }

    function setDeployGasLimit(uint64 deployGasLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_deployGasLimit = deployGasLimit;
    }

    function setDefaultGasConfig(uint64 fixedGas, uint64 dynamicGas) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_defaultFixedGas = fixedGas;
        s_defaultDynamicGas = dynamicGas;
    }

    function setERC721PoolBeaconData(address upgradeableBeacon, address beaconProxy)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        s_erc721PoolUpgradeableBeacon = IBeacon(upgradeableBeacon);
        s_erc721PoolBeaconProxy = beaconProxy;
    }

    function getDeployConfig(
        PoolType poolType,
        bytes32 salt,
        address sender,
        address token,
        uint64 chainSelector,
        uint16 limitTransferPerRequest
    ) external view returns (DeployConfig memory) {
        return DeployConfig({
            pool: predictPoolAddress(poolType, salt, sender, chainSelector),
            token: token,
            chainSelector: chainSelector,
            limitTransferPerRequest: limitTransferPerRequest
        });
    }

    function getSalt(PoolType poolType, bytes32 senderSalt, address sender, uint64 chainSelector)
        public
        view
        returns (bytes32)
    {
        if (poolType != PoolType.ERC721) revert PoolTypeNotSupported(poolType);

        return keccak256(
            abi.encodePacked(
                poolType, senderSalt, sender, chainSelector, s_erc721PoolUpgradeableBeacon.implementation().codehash
            )
        );
    }

    function predictPoolAddress(PoolType poolType, bytes32 senderSalt, address sender, uint64 chainSelector)
        public
        view
        returns (address)
    {
        if (poolType != PoolType.ERC721) revert PoolTypeNotSupported(poolType);

        return s_erc721PoolBeaconProxy.predictDeterministicAddress(getSalt(poolType, senderSalt, sender, chainSelector));
    }

    function getFee(IERC20 feeToken, uint64 remoteChainSelector)
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
            gasLimit: s_deployGasLimit,
            data: abi.encode(uint8(0), bytes32(0), address(0), empty, empty)
        });
    }

    function deployERC721TokenPool(
        bytes32 salt,
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
            address actual = predictPoolAddress(PoolType.ERC721, salt, msg.sender, remote.chainSelector);
            if (remote.pool != actual) revert PredictAddressNotMatch(remote.pool, actual);
            if (local.limitTransferPerRequest == 0) revert InvalidTransferLimitPerRequest();

            _sendDataPayFeeToken({
                destChainSelector: remote.chainSelector,
                receiver: s_remoteFactories[remote.chainSelector],
                feeToken: feeToken,
                gasLimit: s_deployGasLimit,
                data: abi.encode(PoolType.ERC721, salt, msg.sender, remote, local)
            });
        }

        _deployERC721TokenPoolAndInit(salt, msg.sender, local, remote);
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
        override(CCIPCrossChainSenderReceiver, AccessControlEnumerable)
        returns (bool)
    {
        return AccessControlEnumerable.supportsInterface(interfaceId)
            || CCIPCrossChainSenderReceiver.supportsInterface(interfaceId);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal virtual override whenNotPaused {
        (PoolType poolType, bytes32 salt, address owner, DeployConfig memory local, DeployConfig memory remote) =
            abi.decode(message.data, (PoolType, bytes32, address, DeployConfig, DeployConfig));

        if (poolType != PoolType.ERC721) revert PoolTypeNotSupported(poolType);

        _deployERC721TokenPoolAndInit(salt, owner, local, remote);
    }

    function _deployERC721TokenPoolAndInit(
        bytes32 salt,
        address owner,
        DeployConfig memory local,
        DeployConfig memory remote
    ) internal {
        address actual =
            s_erc721PoolBeaconProxy.cloneDeterministic(getSalt(PoolType.ERC721, salt, owner, s_currentChainSelector));
        if (local.pool != actual) revert PredictAddressNotMatch(local.pool, actual);
        if (remote.limitTransferPerRequest == 0) revert InvalidTransferLimitPerRequest();

        // Initialize the localPool
        IERC721TokenPool(local.pool).initialize(
            address(this),
            address(s_router),
            local.token,
            s_currentChainSelector,
            s_defaultFixedGas,
            s_defaultDynamicGas
        );
        if (remote.pool != address(0)) {
            IERC721TokenPool(local.pool).addRemotePool(remote.chainSelector, remote.pool);
            IERC721TokenPool(local.pool).setTransferLimitPerRequest(
                remote.chainSelector, remote.limitTransferPerRequest
            );
        }
        IOwnable(local.pool).transferOwnership(owner);
    }
}
