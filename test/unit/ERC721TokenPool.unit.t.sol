// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
// import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

// import {Test} from "forge-std/Test.sol";
// import {console} from "forge-std/console.sol";

// import {IERC721TokenPool, ERC721TokenPool} from "src/ERC721TokenPool.sol";
// import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
// import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
// import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import {NFTPoolFactory} from "src/NFTPoolFactory.sol";

// import {ERC721Mintable} from "test/mocks/ERC721Mintable.sol";
// import {MockRmnProxy} from "test/mocks/MockRmnProxy.sol";

// contract ERC721TokenPoolUnitTest is Test {
//     enum Scenario {
//         OwnedByPool,
//         OwnedByExternalStorage,
//         NotMintedButHaveMinterRole,
//         NotMintedButNotHaveMinterRole
//     }

//     address internal universalDeployer;

//     NFTPoolFactory internal lcFactory;
//     NFTPoolFactory internal rmFactory;

//     MockRmnProxy internal lcRmnProxy;
//     MockRmnProxy internal rmRmnProxy;

//     BeaconProxy internal localBeaconProxy;
//     BeaconProxy internal remoteBeaconProxy;

//     UpgradeableBeacon internal localBeacon;
//     UpgradeableBeacon internal remoteBeacon;

//     ERC721Mintable internal lcNFT;
//     ERC721Mintable internal rmNFT;

//     uint256 internal localForkId;
//     uint256 internal remoteForkId;

//     Register.NetworkDetails internal lcNwDts;
//     Register.NetworkDetails internal rmNwDts;
//     CCIPLocalSimulator internal ccipLocalSimulator;
//     CCIPLocalSimulator internal ccipRemoteSimulator;
//     CCIPLocalSimulatorFork internal ccipLocalSimulatorFork;

//     address internal owner;
//     address internal pauser;
//     address internal admin;
//     address internal proxyAdmin;

//     function setUp() public {
//         owner = makeAddr("owner");
//         pauser = makeAddr("pauser");
//         admin = makeAddr("admin");
//         proxyAdmin = makeAddr("proxyAdmin");
//         universalDeployer = makeAddr("universalDeployer");

//         remoteForkId = vm.createFork("sepolia-local");
//         localForkId = vm.createSelectFork("ronin-local");

//         ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
//         vm.makePersistent(address(ccipLocalSimulatorFork));
        

//         ccipLocalSimulatorFork.setNetworkDetails(
//             2021,
//             Register.NetworkDetails(
//                 13116810400804392105, // Ronin Saigon chain selector
//                 0x0aCAe4e51D3DA12Dd3F45A66e8b660f740e6b820, // routerAddress
//                 0x5bB50A6888ee6a67E22afFDFD9513be7740F1c15, // linkAddress
//                 0xA959726154953bAe111746E265E6d754F48570E6, // wrappedNativeAddress
//                 0x88DD2416699Bad3AeC58f535BC66F7f62DE2B2EC, // ccipBnMAddress
//                 0x04B1F917a3ba69Fa252564414DdAFc82fA1B5178, // ccipLnMAddress
//                 0xceA253a8c2BB995054524d071498281E89aACD59, // rmnProxyAddress
//                 0x5055DA89A16b71fEF91D1af323b139ceDe2d8320, // registryModuleOwnerCustomAddress
//                 0x90e83d532A4aD13940139c8ACE0B93b0DdbD323a // tokenAdminRegistryAddress
//             )
//         );

//         // Step 1) Deploy CCIPxRoninNFTGateway.sol to Ethereum Sepolia
//         assertEq(vm.activeFork(), remoteForkId);

//         rmNwDts = ccipLocalSimulatorFork.getNetworkDetails(block.chainid); // we are currently on Ethereum Sepolia Fork
//         assertEq(
//             rmNwDts.chainSelector,
//             16015286601757825753,
//             "Sanity check: Ethereum Sepolia chain selector should be 16015286601757825753"
//         );

//         vm.startPrank(universalDeployer);
//         rmNFT = new ERC721Mintable();
//         vm.label(address(rmNFT), "rmNFT");
//         rmNFT.initialize("Remote NFT", "rNFT");
//         rmFactory = NFTPoolFactory(
//             address(
//                 new TransparentUpgradeableProxy(
//                     address(new NFTPoolFactory()),
//                     admin,
//                     abi.encodeCall(
//                         NFTPoolFactory.initialize,
//                         (admin, pauser, rmNwDts.routerAddress, rmNwDts.chainSelector, 1_000_000, 100_000, 200_000)
//                     )
//                 )
//             )
//         );
//         vm.label(address(rmFactory), "rmFactory");
//         remoteBeacon = new UpgradeableBeacon(address(new ERC721TokenPool()), owner);
//         vm.label(address(remoteBeacon), "remoteBeacon");
//         remoteBeaconProxy = new BeaconProxy(address(remoteBeacon), "");
//         vm.label(address(remoteBeaconProxy), "remoteBeaconProxy");
//         vm.stopPrank();

//         bytes32 expectedCodeHash = remoteBeacon.implementation().codehash;

//         vm.selectFork(localForkId);
//         assertEq(vm.activeFork(), localForkId);

//         lcNwDts = ccipLocalSimulatorFork.getNetworkDetails(block.chainid); // we are currently on Ronin Saigon Fork
//         assertEq(
//             lcNwDts.chainSelector,
//             13116810400804392105,
//             "Sanity check: Saigon chain selector should be 13116810400804392105"
//         );

//         vm.startPrank(universalDeployer);
//         lcNFT = new ERC721Mintable();
//         lcNFT.initialize("Local NFT", "lNFT");
//         vm.label(address(lcNFT), "lcNFT");
//         lcFactory = NFTPoolFactory(
//             address(
//                 new TransparentUpgradeableProxy(
//                     address(new NFTPoolFactory()),
//                     admin,
//                     abi.encodeCall(
//                         NFTPoolFactory.initialize,
//                         (admin, pauser, lcNwDts.routerAddress, lcNwDts.chainSelector, 1_000_000, 100_000, 200_000)
//                     )
//                 )
//             )
//         );
//         vm.label(address(lcFactory), "lcFactory");
//         localBeacon = new UpgradeableBeacon(address(new ERC721TokenPool()), owner);
//         vm.label(address(localBeacon), "localBeacon");
//         localBeaconProxy = new BeaconProxy(address(localBeacon), "");
//         vm.label(address(localBeaconProxy), "localBeaconProxy");
//         vm.stopPrank();

//         bytes32 gotCodeHash = localBeacon.implementation().codehash;

//         vm.startPrank(admin);
//         lcFactory.setERC721PoolBeaconData(address(localBeacon), address(localBeaconProxy));
//         lcFactory.addRemoteFactory(rmNwDts.chainSelector, address(rmFactory));
//         vm.stopPrank();

//         vm.selectFork(remoteForkId);
//         vm.startPrank(admin);
//         rmFactory.setERC721PoolBeaconData(address(remoteBeacon), address(remoteBeaconProxy));
//         rmFactory.addRemoteFactory(lcNwDts.chainSelector, address(lcFactory));
//         vm.stopPrank();

//         vm.selectFork(localForkId);

//         assertTrue(
//             expectedCodeHash == gotCodeHash,
//             "Sanity check: codehash of the local beacon should be equal to the codehash of the remote beacon"
//         );
//     }

//     function _deployDualPool()
//         internal
//         returns (NFTPoolFactory.DeployConfig memory local, NFTPoolFactory.DeployConfig memory remote)
//     {
//         bytes32 salt = keccak256("salt");
//         bool crossDeploy = true;

//         NFTPoolFactory.PoolType poolType = NFTPoolFactory.PoolType.ERC721;
//         local = lcFactory.getDeployConfig(poolType, salt, owner, address(lcNFT), lcNwDts.chainSelector, 10);
//         remote = lcFactory.getDeployConfig(poolType, salt, owner, address(rmNFT), rmNwDts.chainSelector, 10);

//         IERC20 feeToken = IERC20(lcNwDts.linkAddress);
//         uint256 fee = lcFactory.getFee(feeToken, remote.chainSelector);
//         deal(address(feeToken), owner, fee);

//         vm.startPrank(owner);
//         IERC20(lcNwDts.linkAddress).approve(address(lcFactory), fee);
//         lcFactory.deployERC721TokenPool(salt, feeToken, crossDeploy, local, remote);
//         ERC721TokenPool(local.pool).acceptOwnership();
//         vm.stopPrank();

//         assertTrue(local.pool.code.length > 0, "Local pool should be deployed");

//         ccipLocalSimulator.switchChainAndRouteMessage(remoteForkId);
//         assertTrue(
//             remote.pool.code.length > 0,
//             "Remote pool should be deployed after the message is routed to the remote chain"
//         );

//         vm.prank(owner);
//         ERC721TokenPool(remote.pool).acceptOwnership();

//         vm.selectFork(localForkId);
//     }

//     function _getIds(uint256 startId, uint256 endId) internal pure returns (uint256[] memory ids) {
//         ids = new uint256[](endId - startId + 1);
//         for (uint256 i = startId; i <= endId; i++) {
//             ids[i - startId] = i;
//         }
//     }

//     function _slice(uint256[] memory arr, uint256 start, uint256 end) internal pure returns (uint256[] memory) {
//         require(start < end && end <= arr.length, "Invalid slice range");
//         uint256[] memory result = new uint256[](end - start);
//         for (uint256 i = start; i < end; i++) {
//             result[i - start] = arr[i];
//         }
//         return result;
//     }

//     function testConcrete_RevertIf_ExceedsLimitTransferPerRequest() public {
//         (NFTPoolFactory.DeployConfig memory local, NFTPoolFactory.DeployConfig memory remote) = _deployDualPool();

//         address alice = makeAddr("alice");
//         address bob = makeAddr("bob");

//         vm.selectFork(localForkId);
//         uint256[] memory ids = _getIds(1, 11); // [1, 2, 3, ..., 11]
//         lcNFT.mintBatch(alice, ids);

//         IERC20 feeToken = IERC20(lcNwDts.wrappedNativeAddress);
//         uint256 fee = ERC721TokenPool(local.pool).getFee(feeToken, remote.chainSelector, ids.length);
//         deal(address(feeToken), alice, fee);

//         vm.startPrank(alice);
//         lcNFT.setApprovalForAll(local.pool, true);
//         feeToken.approve(local.pool, fee);
//         vm.expectRevert(abi.encodeWithSelector(IERC721TokenPool.ExceedsTransferLimit.selector, 11, 10));
//         ERC721TokenPool(local.pool).crossBatchTransfer(bob, ids, remote.chainSelector, feeToken);
//         vm.stopPrank();
//     }

//     function testConcrete_SuccessWhen_ReleaseUsingExternalStorage() public {
//         (NFTPoolFactory.DeployConfig memory local, NFTPoolFactory.DeployConfig memory remote) = _deployDualPool();

//         IERC20 feeToken = IERC20(lcNwDts.linkAddress);
//         address alice = makeAddr("alice");
//         address bob = makeAddr("bob");

//         vm.selectFork(remoteForkId);
//         address externalStorage = makeAddr("externalStorage");
//         uint256[] memory ids = _getIds(1, 10); // [1, 2, 3, ..., 10]
//         rmNFT.mintBatch(externalStorage, _slice(ids, 0, 5)); // mint [1, 2, 3, 4, 5]

//         vm.prank(externalStorage);
//         rmNFT.setApprovalForAll(remote.pool, true);
//         vm.prank(owner);
//         ERC721TokenPool(remote.pool).setExternalStorage(externalStorage);

//         vm.selectFork(localForkId);
//         lcNFT.mintBatch(alice, ids);

//         uint256 fee = ERC721TokenPool(local.pool).getFee(feeToken, remote.chainSelector, ids.length);
//         deal(address(feeToken), alice, fee);

//         vm.startPrank(alice);
//         lcNFT.setApprovalForAll(local.pool, true);
//         feeToken.approve(local.pool, fee);
//         ERC721TokenPool(local.pool).crossBatchTransfer(bob, ids, remote.chainSelector, feeToken);
//         vm.stopPrank();

//         assertEq(lcNFT.balanceOf(alice), 0, "Alice should not have any tokens");
//         assertEq(lcNFT.balanceOf(local.pool), 10, "Local pool should have 10 tokens");

//         ccipLocalSimulator.switchChainAndRouteMessage(remoteForkId);
//         assertEq(rmNFT.balanceOf(bob), 10, "Bob should have 10 tokens");
//         assertEq(rmNFT.balanceOf(externalStorage), 0, "External storage should not have any tokens");
//         assertEq(rmNFT.balanceOf(remote.pool), 0, "Remote pool should not have any tokens");
//     }

//     function testConcrete_SuccessWhen_ReleaseOrMint() public {
//         (NFTPoolFactory.DeployConfig memory local, NFTPoolFactory.DeployConfig memory remote) = _deployDualPool();

//         address alice = makeAddr("alice");
//         address bob = makeAddr("bob");

//         vm.selectFork(remoteForkId);
//         uint256[] memory ids = _getIds(1, 3); // [1, 2, 3]
//         rmNFT.mintBatch(address(this), _slice(ids, 0, 2)); // mint [1, 2]
//         rmNFT.transferFrom(address(this), remote.pool, ids[0]);
//         rmNFT.transferFrom(address(this), remote.pool, ids[1]);
//         assertEq(rmNFT.balanceOf(remote.pool), 2, "Should have 2 token");

//         vm.selectFork(localForkId);
//         lcNFT.mintBatch(alice, ids);

//         IERC20 feeToken = IERC20(lcNwDts.wrappedNativeAddress);
//         uint256 fee = ERC721TokenPool(local.pool).getFee(feeToken, remote.chainSelector, ids.length);
//         deal(address(feeToken), alice, fee);

//         vm.startPrank(alice);
//         lcNFT.setApprovalForAll(local.pool, true);
//         feeToken.approve(local.pool, fee);
//         ERC721TokenPool(local.pool).crossBatchTransfer(bob, ids, remote.chainSelector, feeToken);
//         vm.stopPrank();

//         assertEq(lcNFT.balanceOf(alice), 0, "Alice should not have any tokens");
//         assertEq(lcNFT.balanceOf(local.pool), 3, "Local pool should have 3 tokens");
//         assertEq(lcNFT.ownerOf(1), local.pool, "Local pool should be the owner of token 1");
//         assertEq(lcNFT.ownerOf(2), local.pool, "Local pool should be the owner of token 2");
//         assertEq(lcNFT.ownerOf(3), local.pool, "Local pool should be the owner of token 3");

//         ccipLocalSimulator.switchChainAndRouteMessage(remoteForkId);
//         assertEq(rmNFT.balanceOf(bob), 3, "Bob should have 3 tokens");
//         assertEq(rmNFT.ownerOf(1), bob, "Bob should be the owner of token 1");
//         assertEq(rmNFT.ownerOf(2), bob, "Bob should be the owner of token 2");
//         assertEq(rmNFT.ownerOf(3), bob, "Bob should be the owner of token 3");

//         assertEq(rmNFT.balanceOf(remote.pool), 0, "Remote pool should not have any tokens");
//     }

//     function testConcrete_SuccessWhen_DeployDualPools() public {
//         (NFTPoolFactory.DeployConfig memory local, NFTPoolFactory.DeployConfig memory remote) = _deployDualPool();
//         IERC20 feeToken = IERC20(lcNwDts.linkAddress);

//         address alice = makeAddr("alice");
//         address bob = makeAddr("bob");

//         lcNFT.mint(alice, 1);
//         uint256 fee = ERC721TokenPool(local.pool).getFee(feeToken, remote.chainSelector, 1);
//         deal(address(feeToken), alice, fee);
//         uint256[] memory ids = new uint256[](1);
//         ids[0] = 1;

//         vm.startPrank(alice);
//         lcNFT.approve(address(local.pool), 1);
//         feeToken.approve(local.pool, fee);
//         ERC721TokenPool(local.pool).crossBatchTransfer(bob, ids, remote.chainSelector, feeToken);
//         vm.stopPrank();

//         assertEq(lcNFT.balanceOf(alice), 0, "Alice should not have any tokens");
//         assertEq(lcNFT.balanceOf(local.pool), 1, "Local pool should have 1 token");
//         assertEq(lcNFT.ownerOf(1), local.pool, "Local pool should be the owner of token 1");

//         ccipLocalSimulator.switchChainAndRouteMessage(remoteForkId);

//         assertEq(rmNFT.balanceOf(bob), 1, "Bob should have 1 token");
//         assertEq(rmNFT.ownerOf(1), bob, "Bob should be the owner of token 1");

//         feeToken = IERC20(rmNwDts.linkAddress);
//         fee = ERC721TokenPool(remote.pool).getFee(feeToken, local.chainSelector, 1);
//         deal(address(feeToken), bob, fee);

//         vm.startPrank(bob);
//         rmNFT.approve(address(remote.pool), 1);
//         feeToken.approve(remote.pool, fee);
//         ERC721TokenPool(remote.pool).crossBatchTransfer(alice, ids, local.chainSelector, feeToken);
//         vm.stopPrank();

//         assertEq(rmNFT.balanceOf(bob), 0, "Bob should not have any tokens");
//         assertEq(rmNFT.balanceOf(remote.pool), 1, "Remote pool should have 1 token");
//         assertEq(rmNFT.ownerOf(1), remote.pool, "Remote pool should be the owner of token 1");

//         ccipLocalSimulator.switchChainAndRouteMessage(localForkId);
//         assertEq(lcNFT.balanceOf(alice), 1, "Alice should have 1 token");
//         assertEq(lcNFT.ownerOf(1), alice, "Alice should be the owner of token 1");
//         assertEq(lcNFT.balanceOf(local.pool), 0, "Local pool should not have any tokens");
//     }
// }
