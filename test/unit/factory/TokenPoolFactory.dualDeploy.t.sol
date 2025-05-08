// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TokenPoolFactory} from "src/TokenPoolFactory.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {SingleLockMintERC721Pool} from "src/pools/erc721/SingleLockMintERC721Pool.sol";
import {CCIPLocalSimulator} from "test/mocks/CCIPLocalSimulator.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {ITokenPoolFactory} from "src/interfaces/ITokenPoolFactory.sol";
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

    address blueprint = _createBlueprint(type(SingleLockMintERC721Pool).creationCode);

    uint32 deployGas = 2_000_000;
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
