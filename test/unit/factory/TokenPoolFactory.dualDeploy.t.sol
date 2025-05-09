// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TokenPoolFactory} from "src/TokenPoolFactory.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {SingleLockMintERC721Pool} from "src/pools/erc721/SingleLockMintERC721Pool.sol";
import {CCIPLocalSimulator} from "test/simulators/CCIPLocalSimulator.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ITokenPoolFactory} from "src/interfaces/ITokenPoolFactory.sol";
import {ITokenPoolCallback} from "src/interfaces/pools/ITokenPoolCallback.sol";
import {MockERC721Mintable} from "test/mocks/MockERC721Mintable.sol";

contract TokenPoolFactory_DualDeployTest is Test {
    address admin = makeAddr("admin");
    address beaconOwner = makeAddr("beaconOwner");

    uint64 currentChainSelector = uint64(vm.unixTime());
    uint64 remoteChainSelector = uint64(~vm.unixTime());

    CCIPLocalSimulator localSimulator = new CCIPLocalSimulator();

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    TokenPoolFactory localFactory;
    TokenPoolFactory remoteFactory;

    MockERC721Mintable localToken = new MockERC721Mintable("LocalToken", "LT");
    MockERC721Mintable remoteToken = new MockERC721Mintable("RemoteToken", "RT");

    bytes32 constant TOKEN_POOL_OWNER_ROLE = keccak256("TOKEN_POOL_OWNER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 constant RATE_LIMITER_ROLE = keccak256("RATE_LIMITER_ROLE");
    bytes32 constant SHARED_STORAGE_SETTER_ROLE = keccak256("SHARED_STORAGE_SETTER_ROLE");

    address blueprint = _createBlueprint(type(SingleLockMintERC721Pool).creationCode);

    uint32 deployGas = 1_500_000;
    uint32 fixedGas = 200_000;
    uint32 dynamicGas = 100_000;

    function setUp() public {
        localSimulator.supportChain(currentChainSelector);
        localSimulator.supportChain(remoteChainSelector);

        localFactory = TokenPoolFactory(
            address(
                new TransparentUpgradeableProxy(
                    address(new TokenPoolFactory()),
                    admin,
                    abi.encodeCall(
                        TokenPoolFactory.initialize,
                        (
                            admin,
                            address(localSimulator.tokenAdminRegistry()),
                            address(localSimulator.router()),
                            currentChainSelector
                        )
                    )
                )
            )
        );

        remoteFactory = TokenPoolFactory(
            address(
                new TransparentUpgradeableProxy(
                    address(new TokenPoolFactory()),
                    admin,
                    abi.encodeCall(
                        TokenPoolFactory.initialize,
                        (
                            admin,
                            address(localSimulator.tokenAdminRegistry()),
                            address(localSimulator.router()),
                            remoteChainSelector
                        )
                    )
                )
            )
        );

        vm.label(address(localFactory), "LocalFactory");
        vm.label(address(remoteFactory), "RemoteFactory");

        vm.startPrank(admin);
        // Local Setup
        localFactory.addRemoteFactory(remoteChainSelector, address(remoteFactory));
        localFactory.addBlueprint(blueprint, deployGas, fixedGas, dynamicGas);
        // Remote Setup
        remoteFactory.addRemoteFactory(currentChainSelector, address(localFactory));
        remoteFactory.addBlueprint(blueprint, deployGas, fixedGas, dynamicGas);
        vm.stopPrank();
        localSimulator.switchChain(currentChainSelector);
    }

    function testFuzz_RevertIf_Blueprint_NotSupported(
        address notBlueprint,
        address creator,
        address token,
        bool currentChain
    ) external {
        vm.assume(creator != address(0));
        vm.assume(notBlueprint != blueprint);

        vm.expectRevert();
        localFactory.predictPool(
            notBlueprint, creator, currentChain ? currentChainSelector : remoteChainSelector, token
        );
    }

    function testConcrete_RevertIf_DualDeploy_SingleChain() external {
        ITokenPoolFactory.DeployConfig memory local =
            localFactory.getDeployConfig(blueprint, alice, currentChainSelector, address(localToken));
        ITokenPoolFactory.DeployConfig memory remote =
            localFactory.getDeployConfig(blueprint, alice, remoteChainSelector, address(remoteToken));

        address[] memory feeTokens = localFactory.getFeeTokens(remoteChainSelector);
        assertTrue(feeTokens.length > 0, "Fee tokens length mismatch");

        uint256 fee = localFactory.estimateFee(address(0), blueprint, remoteChainSelector);
        assertTrue(fee > 0, "Fee should be greater than 0");

        deal(alice, fee);
        vm.prank(alice);
        vm.expectRevert();
        localFactory.dualDeployPool{value: fee}(address(0), local, local);

        vm.prank(alice);
        vm.expectRevert();
        localFactory.dualDeployPool{value: fee}(address(0), remote, remote);

        vm.prank(alice);
        vm.expectRevert();
        localFactory.dualDeployPool{value: fee}(address(0), remote, local);
    }

    function testFuzz_PoolAddress_NotMatch_If_Calculated_From_Different_Chain(
        address localCreator,
        address remoteCreator,
        address tokenLocal,
        address tokenRemote,
        bool localSeed,
        bool remoteSeed
    ) external view {
        vm.assume(localCreator != address(0));
        vm.assume(remoteCreator != address(0));

        address a = localFactory.predictPool(
            blueprint, localCreator, localSeed ? currentChainSelector : remoteChainSelector, tokenLocal
        );
        address b = remoteFactory.predictPool(
            blueprint, remoteCreator, remoteSeed ? currentChainSelector : remoteChainSelector, tokenRemote
        );

        assertTrue(a != b, "Local and remote pools should not be the same");
    }

    function testConcrete_RevertIf_Sender_NotCreator_DualDeploy() external {
        ITokenPoolFactory.DeployConfig memory local =
            localFactory.getDeployConfig(blueprint, alice, currentChainSelector, address(localToken));
        ITokenPoolFactory.DeployConfig memory remote =
            localFactory.getDeployConfig(blueprint, alice, remoteChainSelector, address(remoteToken));

        address[] memory feeTokens = localFactory.getFeeTokens(remoteChainSelector);
        assertTrue(feeTokens.length > 0, "Fee tokens length mismatch");

        uint256 fee = localFactory.estimateFee(address(0), blueprint, remoteChainSelector);
        assertTrue(fee > 0, "Fee should be greater than 0");

        deal(bob, fee);
        vm.prank(bob);
        vm.expectRevert();
        localFactory.dualDeployPool{value: fee}(address(0), local, remote);
    }

    function testConcrete_getDeployConfig_PoolAddress_ShouldMatch_PredictPool() external view {
        ITokenPoolFactory.DeployConfig memory local =
            localFactory.getDeployConfig(blueprint, alice, currentChainSelector, address(localToken));
        ITokenPoolFactory.DeployConfig memory remote =
            localFactory.getDeployConfig(blueprint, alice, remoteChainSelector, address(remoteToken));

        assertEq(
            local.pool,
            localFactory.predictPool(blueprint, alice, currentChainSelector, address(localToken)),
            "Local pool address mismatch"
        );
        assertEq(
            remote.pool,
            localFactory.predictPool(blueprint, alice, remoteChainSelector, address(remoteToken)),
            "Remote pool address mismatch"
        );
    }

    function testConcrete_RevertIf_Creator_Redeploy_DualDeploy() external {
        ITokenPoolFactory.DeployConfig memory local =
            localFactory.getDeployConfig(blueprint, alice, currentChainSelector, address(localToken));
        ITokenPoolFactory.DeployConfig memory remote =
            localFactory.getDeployConfig(blueprint, alice, remoteChainSelector, address(remoteToken));

        address[] memory feeTokens = localFactory.getFeeTokens(remoteChainSelector);
        assertTrue(feeTokens.length > 0, "Fee tokens length mismatch");

        uint256 fee = localFactory.estimateFee(address(0), blueprint, remoteChainSelector);
        assertTrue(fee > 0, "Fee should be greater than 0");

        deal(alice, fee);
        vm.prank(alice);
        localFactory.dualDeployPool{value: fee}(address(0), local, remote);

        deal(alice, fee);
        vm.expectRevert();
        vm.prank(alice);
        localFactory.dualDeployPool{value: fee}(address(0), local, remote);
    }

    function testConcrete_AddressNotMatchWhenDeploy_DifferentChain() external {
        address creator = makeAddr("creator");

        ITokenPoolFactory.DeployConfig memory local1 =
            localFactory.getDeployConfig(blueprint, creator, currentChainSelector, address(localToken));
        ITokenPoolFactory.DeployConfig memory remote1 =
            localFactory.getDeployConfig(blueprint, creator, remoteChainSelector, address(remoteToken));

        ITokenPoolFactory.DeployConfig memory local2 =
            remoteFactory.getDeployConfig(blueprint, creator, remoteChainSelector, address(remoteToken));
        ITokenPoolFactory.DeployConfig memory remote2 =
            remoteFactory.getDeployConfig(blueprint, creator, currentChainSelector, address(localToken));

        assertTrue(
            local1.pool != remote2.pool && remote1.pool != local2.pool, "Local and remote pools should not be the same"
        );

        // Assert no address collision
        ITokenPoolFactory.DeployConfig[] memory localPools = new ITokenPoolFactory.DeployConfig[](4);
        localPools[0] = local1;
        localPools[1] = remote1;
        localPools[2] = local2;
        localPools[3] = remote2;

        for (uint256 i = 0; i < localPools.length; ++i) {
            for (uint256 j = i + 1; j < localPools.length; ++j) {
                assertTrue(localPools[i].pool != localPools[j].pool, "Local and remote pools should not be the same");
            }
        }
    }

    function testFuzz_DualDeploy(address deployer, bool localOrRemoteFactory) external {
        vm.assume(deployer != address(0));
        TokenPoolFactory m_localFactory = localOrRemoteFactory ? localFactory : remoteFactory;
        TokenPoolFactory m_remoteFactory = localOrRemoteFactory ? remoteFactory : localFactory;
        address m_localToken = localOrRemoteFactory ? address(localToken) : address(remoteToken);
        address m_remoteToken = localOrRemoteFactory ? address(remoteToken) : address(localToken);
        uint64 m_currentChainSelector = localOrRemoteFactory ? currentChainSelector : remoteChainSelector;
        uint64 m_remoteChainSelector = localOrRemoteFactory ? remoteChainSelector : currentChainSelector;
        localSimulator.switchChain(m_currentChainSelector);

        ITokenPoolFactory.DeployConfig memory local =
            m_localFactory.getDeployConfig(blueprint, deployer, m_currentChainSelector, m_localToken);
        ITokenPoolFactory.DeployConfig memory remote =
            m_localFactory.getDeployConfig(blueprint, deployer, m_remoteChainSelector, m_remoteToken);

        address[] memory feeTokens = m_localFactory.getFeeTokens(m_remoteChainSelector);
        assertTrue(feeTokens.length > 0, "Fee tokens length mismatch");

        uint256 fee = m_localFactory.estimateFee(address(0), blueprint, m_remoteChainSelector);
        assertTrue(fee > 0, "Fee should be greater than 0");

        deal(deployer, fee);
        vm.prank(deployer);
        m_localFactory.dualDeployPool{value: fee}(address(0), local, remote);

        assertTrue(ITokenPoolCallback(local.pool).hasRole(0x0, address(m_localFactory)), "Local pool ADMIN mismatch");
        assertTrue(
            ITokenPoolCallback(local.pool).hasRole(TOKEN_POOL_OWNER_ROLE, address(m_localFactory)),
            "Local pool TOKEN_POOL_OWNER_ROLE mismatch"
        );
        assertTrue(
            ITokenPoolCallback(local.pool).hasRole(PAUSER_ROLE, address(m_localFactory)),
            "Local pool PAUSER_ROLE mismatch"
        );
        assertTrue(
            ITokenPoolCallback(local.pool).hasRole(RATE_LIMITER_ROLE, address(m_localFactory)),
            "Local pool RATE_LIMITER_ROLE mismatch"
        );
        assertTrue(
            ITokenPoolCallback(local.pool).hasRole(SHARED_STORAGE_SETTER_ROLE, address(m_localFactory)),
            "Local pool SHARED_STORAGE_SETTER_ROLE mismatch"
        );

        assertFalse(ITokenPoolCallback(local.pool).hasRole(0x0, address(deployer)), "Local pool role mismatch");
        assertTrue(
            ITokenPoolCallback(local.pool).hasRole(TOKEN_POOL_OWNER_ROLE, address(deployer)), "Local pool role mismatch"
        );
        assertTrue(ITokenPoolCallback(local.pool).hasRole(PAUSER_ROLE, address(deployer)), "Local pool role mismatch");
        assertTrue(
            ITokenPoolCallback(local.pool).hasRole(RATE_LIMITER_ROLE, address(deployer)), "Local pool role mismatch"
        );
        assertTrue(
            ITokenPoolCallback(local.pool).hasRole(SHARED_STORAGE_SETTER_ROLE, address(deployer)),
            "Local pool role mismatch"
        );

        assertTrue(ITokenPoolCallback(remote.pool).hasRole(0x0, address(m_remoteFactory)), "Remote pool role mismatch");
        assertTrue(
            ITokenPoolCallback(remote.pool).hasRole(TOKEN_POOL_OWNER_ROLE, address(m_remoteFactory)),
            "Remote pool role mismatch"
        );
        assertTrue(
            ITokenPoolCallback(remote.pool).hasRole(PAUSER_ROLE, address(m_remoteFactory)), "Remote pool role mismatch"
        );
        assertTrue(
            ITokenPoolCallback(remote.pool).hasRole(RATE_LIMITER_ROLE, address(m_remoteFactory)),
            "Remote pool role mismatch"
        );
        assertTrue(
            ITokenPoolCallback(remote.pool).hasRole(SHARED_STORAGE_SETTER_ROLE, address(m_remoteFactory)),
            "Remote pool role mismatch"
        );

        assertFalse(ITokenPoolCallback(remote.pool).hasRole(0x0, address(deployer)), "Remote pool role mismatch");
        assertTrue(
            ITokenPoolCallback(remote.pool).hasRole(TOKEN_POOL_OWNER_ROLE, address(deployer)),
            "Remote pool role mismatch"
        );
        assertTrue(ITokenPoolCallback(remote.pool).hasRole(PAUSER_ROLE, address(deployer)), "Remote pool role mismatch");
        assertTrue(
            ITokenPoolCallback(remote.pool).hasRole(RATE_LIMITER_ROLE, address(deployer)), "Remote pool role mismatch"
        );
        assertTrue(
            ITokenPoolCallback(remote.pool).hasRole(SHARED_STORAGE_SETTER_ROLE, address(deployer)),
            "Remote pool role mismatch"
        );
    }

    function testConcrete_DualDeploy() external {
        ITokenPoolFactory.DeployConfig memory local =
            localFactory.getDeployConfig(blueprint, alice, currentChainSelector, address(localToken));
        ITokenPoolFactory.DeployConfig memory remote =
            localFactory.getDeployConfig(blueprint, alice, remoteChainSelector, address(remoteToken));

        address[] memory feeTokens = localFactory.getFeeTokens(remoteChainSelector);
        assertTrue(feeTokens.length > 0, "Fee tokens length mismatch");

        uint256 fee = localFactory.estimateFee(address(0), blueprint, remoteChainSelector);
        assertTrue(fee > 0, "Fee should be greater than 0");

        deal(alice, fee);
        vm.prank(alice);
        localFactory.dualDeployPool{value: fee}(address(0), local, remote);

        assertTrue(local.pool.code.length > 0, "Local pool code length mismatch");
        assertTrue(remote.pool.code.length > 0, "Remote pool code length mismatch");
        assertEq(local.pool.codehash, remote.pool.codehash, "Pool code mismatch");

        SingleLockMintERC721Pool localPool = SingleLockMintERC721Pool(local.pool);
        SingleLockMintERC721Pool remotePool = SingleLockMintERC721Pool(remote.pool);

        vm.label(address(localPool), "LocalPool");
        vm.label(address(remotePool), "RemotePool");

        assertTrue(localPool.isSupportedChain(remoteChainSelector), "Local pool supported chain mismatch");
        assertTrue(remotePool.isSupportedChain(currentChainSelector), "Remote pool supported chain mismatch");

        uint256 id = vm.unixTime();
        localToken.mint(alice, id);
        fee = localPool.estimateFee(address(0), remoteChainSelector, 1);
        deal(alice, fee);

        vm.startPrank(alice);
        localToken.approve(address(localPool), id);
        localPool.crossBatchTransfer{value: fee}(remoteChainSelector, (bob), _toSingleton(id), address(0));
        vm.stopPrank();

        assertEq(localToken.ownerOf(id), address(localPool), "Local token owner mismatch");
        assertEq(remoteToken.ownerOf(id), bob, "Remote token owner mismatch");

        fee = remotePool.estimateFee(address(0), currentChainSelector, 1);
        deal(bob, fee);

        localSimulator.switchChain(remoteChainSelector);
        vm.startPrank(bob);
        remoteToken.approve(address(remotePool), id);
        remotePool.crossBatchTransfer{value: fee}(currentChainSelector, (alice), _toSingleton(id), address(0));
        vm.stopPrank();

        assertEq(remoteToken.ownerOf(id), address(remotePool), "Remote token owner mismatch");
        assertEq(localToken.ownerOf(id), alice, "Local token owner mismatch");
    }

    function _toSingleton(uint256 id) internal pure returns (uint256[] memory) {
        uint256[] memory singleton = new uint256[](1);
        singleton[0] = id;
        return singleton;
    }

    function _createBlueprint(bytes memory bytecode) internal returns (address) {
        address logic;
        assembly {
            logic := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(logic != address(0) && logic.code.length > 0, "Failed to deploy logic");

        UpgradeableBeacon beacon = new UpgradeableBeacon(logic, beaconOwner);
        BeaconProxy proxy = new BeaconProxy(address(beacon), "");

        return address(proxy);
    }
}
