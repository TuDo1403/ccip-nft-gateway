// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TokenPoolFactory} from "src/TokenPoolFactory.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {LockMintERC721TokenPool} from "src/pools/erc721/LockMintERC721TokenPool.sol";
import {CCIPLocalSimulator} from "test/mocks/CCIPLocalSimulator.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";
import {ITokenPoolFactory} from "src/interfaces/ITokenPoolFactory.sol";
import {MockERC721Mintable} from "test/mocks/MockERC721Mintable.sol";

contract TokenPoolFactory_DualDeployTest is Test {
    address admin = makeAddr("admin");
    address beaconOwner = makeAddr("beaconOwner");

    CCIPLocalSimulator localSimulator = new CCIPLocalSimulator();

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    TokenPoolFactory localFactory;
    TokenPoolFactory remoteFactory;

    MockERC721Mintable localToken = new MockERC721Mintable("LocalToken", "LT");
    MockERC721Mintable remoteToken = new MockERC721Mintable("RemoteToken", "RT");

    uint64 currentChainSelector = localSimulator.currentChainSelector();
    uint64 remoteChainSelector = localSimulator.remoteChainSelector();

    address blueprint = _createBlueprint(type(LockMintERC721TokenPool).creationCode);

    uint32 deployGas = 2_000_000;
    uint32 fixedGas = 200_000;
    uint32 dynamicGas = 100_000;

    function setUp() public {
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
                            address(localSimulator.rmnProxy()),
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
                            address(localSimulator.rmnProxy()),
                            remoteChainSelector
                        )
                    )
                )
            )
        );

        vm.startPrank(admin);
        // Local Setup
        localFactory.addRemoteFactory(remoteChainSelector, address(remoteFactory), address(localSimulator.router()));
        localFactory.updatePoolConfig(
            ITokenPoolFactory.Standard.ERC721,
            ITokenPoolFactory.PoolType.LockMint,
            deployGas,
            fixedGas,
            dynamicGas,
            blueprint
        );
        // Remote Setup
        remoteFactory.addRemoteFactory(currentChainSelector, address(localFactory), address(localSimulator.router()));
        remoteFactory.updatePoolConfig(
            ITokenPoolFactory.Standard.ERC721,
            ITokenPoolFactory.PoolType.LockMint,
            deployGas,
            fixedGas,
            dynamicGas,
            blueprint
        );
        vm.stopPrank();
    }

    function test_Setup() external {}

    function testConcrete_DualDeploy() external {
        ITokenPoolFactory.Standard std = ITokenPoolFactory.Standard.ERC721;
        ITokenPoolFactory.PoolType pt = ITokenPoolFactory.PoolType.LockMint;

        ITokenPoolFactory.DeployConfig memory local = localFactory.getDeployConfig(
            std, pt, alice, currentChainSelector, currentChainSelector, address(localToken)
        );
        ITokenPoolFactory.DeployConfig memory remote = remoteFactory.getDeployConfig(
            std, pt, alice, currentChainSelector, remoteChainSelector, address(remoteToken)
        );

        address[] memory feeTokens = localFactory.getFeeTokens(remoteChainSelector);
        assertTrue(feeTokens.length > 0, "Fee tokens length mismatch");

        uint256 fee = localFactory.estimateFee(address(0), std, pt, remoteChainSelector);
        assertTrue(fee > 0, "Fee should be greater than 0");

        vm.deal(alice, fee);
        vm.prank(alice);
        localFactory.dualDeployPool{value: fee}(address(0), local, remote);
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
