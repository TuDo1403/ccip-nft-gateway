// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILockReleaseNFTPool} from "src/interfaces/ILockReleaseNFTPool.sol";
import {LockReleaseNFTPool} from "src/LockReleaseNFTPool.sol";
import {EncodeExtraArgs} from "./utils/EncodeExtraArgs.sol";

import {IERC1155Mintable} from "src/interfaces/ext/IERC1155Mintable.sol";
import {IERC721Mintable} from "src/interfaces/ext/IERC721Mintable.sol";

contract LockReleaseNFTPoolTest is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    uint256 public sepoliaFork;
    uint256 public saigonFork;

    Register.NetworkDetails public sepoliaNetworkDetails;
    Register.NetworkDetails public saigonNetworkDetails;

    address public alice;
    address public bob;

    LockReleaseNFTPool public sepoliaPoolERC721;
    LockReleaseNFTPool public saigonPoolERC721;

    LockReleaseNFTPool public sepoliaPoolERC1155;
    LockReleaseNFTPool public saigonPoolERC1155;

    EncodeExtraArgs public encodeExtraArgs;

    address public constant RONIN_GATEWAY_V3 = 0xCee681C9108c42C710c6A8A949307D5F13C9F3ca;
    address public constant MAINCHAIN_GATEWAY_V3 = 0x06855f31dF1d3D25cE486CF09dB49bDa535D2a9e;

    address public constant RONIN_NFT_ERC721 = 0x4226E7Da1B0CB821dd499d020A85ec528FB7f722;
    address public constant SEPOLIA_NFT_ERC721 = 0xAad5541Eb4e5DE1f353BCc8EaBD124fc42107507;

    address public constant RONIN_NFT_ERC1155 = 0xDBB04B4BdBb385EB14cb3ea3C7B1FCcA55ea9160;
    address public constant SEPOLIA_NFT_ERC1155 = 0xFBb71EEE2B420ea88e663B91722b41966E1C5F17;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        sepoliaFork = vm.createSelectFork("sepolia");
        saigonFork = vm.createFork("ronin-testnet");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
        ccipLocalSimulatorFork.setNetworkDetails(
            2021,
            Register.NetworkDetails(
                13116810400804392105, // Ronin Saigon chain selector
                0x0aCAe4e51D3DA12Dd3F45A66e8b660f740e6b820, // routerAddress
                0x5bB50A6888ee6a67E22afFDFD9513be7740F1c15, // linkAddress
                0xA959726154953bAe111746E265E6d754F48570E6, // wrappedNativeAddress
                0x88DD2416699Bad3AeC58f535BC66F7f62DE2B2EC, // ccipBnMAddress
                0x04B1F917a3ba69Fa252564414DdAFc82fA1B5178, // ccipLnMAddress
                0xceA253a8c2BB995054524d071498281E89aACD59, // rmnProxyAddress
                0x5055DA89A16b71fEF91D1af323b139ceDe2d8320, // registryModuleOwnerCustomAddress
                0x90e83d532A4aD13940139c8ACE0B93b0DdbD323a // tokenAdminRegistryAddress
            )
        );

        // Step 1) Deploy LockReleaseNFTPool.sol to Ethereum Sepolia
        assertEq(vm.activeFork(), sepoliaFork);

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid); // we are currently on Ethereum Sepolia Fork
        assertEq(
            sepoliaNetworkDetails.chainSelector,
            16015286601757825753,
            "Sanity check: Ethereum Sepolia chain selector should be 16015286601757825753"
        );

        sepoliaPoolERC721 = new LockReleaseNFTPool(
            sepoliaNetworkDetails.routerAddress,
            MAINCHAIN_GATEWAY_V3,
            SEPOLIA_NFT_ERC721,
            sepoliaNetworkDetails.chainSelector,
            sepoliaNetworkDetails.linkAddress
        );
        sepoliaPoolERC1155 = new LockReleaseNFTPool(
            sepoliaNetworkDetails.routerAddress,
            MAINCHAIN_GATEWAY_V3,
            SEPOLIA_NFT_ERC1155,
            sepoliaNetworkDetails.chainSelector,
            sepoliaNetworkDetails.linkAddress
        );

        // Step 2) Deploy LockReleaseNFTPool.sol to Ronin Saigon
        vm.selectFork(saigonFork);
        assertEq(vm.activeFork(), saigonFork);

        saigonNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid); // we are currently on Ronin Saigon Fork
        assertEq(
            saigonNetworkDetails.chainSelector,
            13116810400804392105,
            "Sanity check: Saigon chain selector should be 13116810400804392105"
        );

        saigonPoolERC721 = new LockReleaseNFTPool(
            saigonNetworkDetails.routerAddress,
            RONIN_GATEWAY_V3,
            RONIN_NFT_ERC721,
            saigonNetworkDetails.chainSelector,
            saigonNetworkDetails.linkAddress
        );
        saigonPoolERC1155 = new LockReleaseNFTPool(
            saigonNetworkDetails.routerAddress,
            RONIN_GATEWAY_V3,
            RONIN_NFT_ERC1155,
            saigonNetworkDetails.chainSelector,
            saigonNetworkDetails.linkAddress
        );
    }

    function testFork_RevertIf_Bridge_ERC721_Saigon_To_Sepolia_ContainsId_ButNotApproveForPool() public {
        uint256 id = vm.unixTime();

        // Step 3) On Ethereum Sepo -lia, call enableChain function
        vm.selectFork(sepoliaFork);
        assertEq(vm.activeFork(), sepoliaFork);

        encodeExtraArgs = new EncodeExtraArgs();

        uint256 gasLimit = 200_000;
        bytes memory extraArgs = encodeExtraArgs.encode(gasLimit);
        assertEq(extraArgs, hex"97a657c90000000000000000000000000000000000000000000000000000000000030d40"); // value taken from https://cll-devrel.gitbook.io/ccip-masterclass-3/ccip-masterclass/exercise-ERC721#step-3-on-ethereum-sepolia-call-enablechain-function

        sepoliaPoolERC721.enableChain(saigonNetworkDetails.chainSelector, address(saigonPoolERC721), extraArgs);

        IERC721Mintable(SEPOLIA_NFT_ERC721).mint(MAINCHAIN_GATEWAY_V3, id);

        // Step 4) On Ronin Saigon, call enableChain function
        vm.selectFork(saigonFork);
        assertEq(vm.activeFork(), saigonFork);

        saigonPoolERC721.enableChain(sepoliaNetworkDetails.chainSelector, address(sepoliaPoolERC721), extraArgs);

        // Step 5) On Ronin Saigon, fund LockReleaseNFTPool.sol with 3 LINK
        assertEq(vm.activeFork(), saigonFork);

        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, 3 ether);

        // Step 6) On Ronin Saigon, mint new ERC721
        assertEq(vm.activeFork(), saigonFork);

        IERC721Mintable(RONIN_NFT_ERC721).mint(alice, id);

        vm.startPrank(alice);
        IERC20(saigonNetworkDetails.linkAddress).approve(address(saigonPoolERC721), 3 ether);
        IERC721Mintable(RONIN_NFT_ERC721).approve(address(saigonPoolERC721), id);

        // Step 7) On Ronin Saigon, crossChainTransfer ERC721
        saigonPoolERC721.crossChainTransfer(
            address(bob), id, 0, sepoliaNetworkDetails.chainSelector, ILockReleaseNFTPool.PayFeesIn.LINK
        );

        vm.stopPrank();

        assertEq(
            IERC721Mintable(RONIN_NFT_ERC721).ownerOf(id), address(saigonPoolERC721), "NFT should be locked in the pool"
        );

        vm.expectRevert();
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork); // THIS LINE REPLACES CHAINLINK CCIP DONs, DO NOT FORGET IT
    }

    function testFork_CanBridge_ERC721_From_Saigon_To_Sepolia_TransferFromGateway() public {
        uint256 id = vm.unixTime();

        // Step 3) On Ethereum Sepo -lia, call enableChain function
        vm.selectFork(sepoliaFork);
        assertEq(vm.activeFork(), sepoliaFork);

        encodeExtraArgs = new EncodeExtraArgs();

        uint256 gasLimit = 200_000;
        bytes memory extraArgs = encodeExtraArgs.encode(gasLimit);
        assertEq(extraArgs, hex"97a657c90000000000000000000000000000000000000000000000000000000000030d40"); // value taken from https://cll-devrel.gitbook.io/ccip-masterclass-3/ccip-masterclass/exercise-ERC721#step-3-on-ethereum-sepolia-call-enablechain-function

        sepoliaPoolERC721.enableChain(saigonNetworkDetails.chainSelector, address(saigonPoolERC721), extraArgs);

        IERC721Mintable(SEPOLIA_NFT_ERC721).mint(MAINCHAIN_GATEWAY_V3, id);
        vm.prank(MAINCHAIN_GATEWAY_V3);
        IERC721Mintable(SEPOLIA_NFT_ERC721).setApprovalForAll(address(sepoliaPoolERC721), true);

        // Step 4) On Ronin Saigon, call enableChain function
        vm.selectFork(saigonFork);
        assertEq(vm.activeFork(), saigonFork);

        saigonPoolERC721.enableChain(sepoliaNetworkDetails.chainSelector, address(sepoliaPoolERC721), extraArgs);

        // Step 5) On Ronin Saigon, fund LockReleaseNFTPool.sol with 3 LINK
        assertEq(vm.activeFork(), saigonFork);

        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, 3 ether);

        // Step 6) On Ronin Saigon, mint new ERC721
        assertEq(vm.activeFork(), saigonFork);

        IERC721Mintable(RONIN_NFT_ERC721).mint(alice, id);

        vm.startPrank(alice);
        IERC20(saigonNetworkDetails.linkAddress).approve(address(saigonPoolERC721), 3 ether);
        IERC721Mintable(RONIN_NFT_ERC721).approve(address(saigonPoolERC721), id);

        // Step 7) On Ronin Saigon, crossChainTransfer ERC721
        saigonPoolERC721.crossChainTransfer(
            address(bob), id, 0, sepoliaNetworkDetails.chainSelector, ILockReleaseNFTPool.PayFeesIn.LINK
        );

        vm.stopPrank();

        assertEq(
            IERC721Mintable(RONIN_NFT_ERC721).ownerOf(id), address(saigonPoolERC721), "NFT should be locked in the pool"
        );

        // On Ethereum Sepolia, check if ERC721 was successfully transferred
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork); // THIS LINE REPLACES CHAINLINK CCIP DONs, DO NOT FORGET IT
        assertEq(vm.activeFork(), sepoliaFork);

        assertEq(IERC721Mintable(SEPOLIA_NFT_ERC721).ownerOf(id), bob, "NFT should be transferred to Bob");
    }

    function testFork_CanBridge_ERC1155_From_SaigonTo_Sepolia_MintSufficientAmount() public {
        address auth = 0xEf46169CD1e954aB10D5e4C280737D9b92d0a936;

        uint256 id = vm.unixTime();

        // Step 3) On Ethereum Sepolia, call enableChain function
        vm.selectFork(sepoliaFork);
        assertEq(vm.activeFork(), sepoliaFork);

        encodeExtraArgs = new EncodeExtraArgs();

        uint256 gasLimit = 200_000;
        bytes memory extraArgs = encodeExtraArgs.encode(gasLimit);
        assertEq(extraArgs, hex"97a657c90000000000000000000000000000000000000000000000000000000000030d40"); // value taken from https://cll-devrel.gitbook.io/ccip-masterclass-3/ccip-masterclass/exercise-ERC721#step-3-on-ethereum-sepolia-call-enablechain-function

        sepoliaPoolERC1155.enableChain(saigonNetworkDetails.chainSelector, address(saigonPoolERC1155), extraArgs);
        vm.startPrank(auth);
        AccessControlEnumerable(SEPOLIA_NFT_ERC1155).grantRole(keccak256("MINTER_ROLE"), address(sepoliaPoolERC1155));
        IERC1155Mintable(SEPOLIA_NFT_ERC1155).mint(MAINCHAIN_GATEWAY_V3, id, 100, "");
        vm.stopPrank();
        
        vm.prank(MAINCHAIN_GATEWAY_V3);
        IERC1155Mintable(SEPOLIA_NFT_ERC1155).setApprovalForAll(address(sepoliaPoolERC1155), true);

        // Step 4) On Ronin Saigon, call enableChain function
        vm.selectFork(saigonFork);
        assertEq(vm.activeFork(), saigonFork);

        saigonPoolERC1155.enableChain(sepoliaNetworkDetails.chainSelector, address(sepoliaPoolERC1155), extraArgs);

        // Step 5) On Ronin Saigon, fund LockReleaseNFTPool.sol with 3 LINK
        assertEq(vm.activeFork(), saigonFork);

        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, 3 ether);

        // Step 6) On Ronin Saigon, mint new ERC1155
        assertEq(vm.activeFork(), saigonFork);

        vm.prank(auth);
        IERC1155Mintable(RONIN_NFT_ERC1155).mint(alice, id, 200, "");

        vm.startPrank(alice);
        IERC20(saigonNetworkDetails.linkAddress).approve(address(saigonPoolERC1155), 3 ether);
        IERC1155Mintable(RONIN_NFT_ERC1155).setApprovalForAll(address(saigonPoolERC1155), true);

        // Step 7) On Ronin Saigon, crossChainTransfer ERC1155
        saigonPoolERC1155.crossChainTransfer(
            address(bob), id, 200, sepoliaNetworkDetails.chainSelector, ILockReleaseNFTPool.PayFeesIn.LINK
        );

        vm.stopPrank();

        assertEq(
            IERC1155Mintable(RONIN_NFT_ERC1155).balanceOf(address(saigonPoolERC1155), id),
            200,
            "NFT should be locked in the pool"
        );

        // On Ethereum Sepolia, check if ERC1155 was successfully transferred
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork); // THIS LINE REPLACES CHAINLINK CCIP DONs, DO NOT FORGET IT
        assertEq(vm.activeFork(), sepoliaFork);

        assertEq(IERC1155Mintable(SEPOLIA_NFT_ERC1155).balanceOf(bob, id), 200, "NFT should be transferred to Bob");
    }

    function testFork_CanBridge_ERC1155_From_Saigon_To_Sepolia_MintWhenIdMissing() public {
        address auth = 0xEf46169CD1e954aB10D5e4C280737D9b92d0a936;

        // Step 3) On Ethereum Sepolia, call enableChain function
        vm.selectFork(sepoliaFork);
        assertEq(vm.activeFork(), sepoliaFork);

        encodeExtraArgs = new EncodeExtraArgs();

        uint256 gasLimit = 200_000;
        bytes memory extraArgs = encodeExtraArgs.encode(gasLimit);
        assertEq(extraArgs, hex"97a657c90000000000000000000000000000000000000000000000000000000000030d40"); // value taken from https://cll-devrel.gitbook.io/ccip-masterclass-3/ccip-masterclass/exercise-ERC721#step-3-on-ethereum-sepolia-call-enablechain-function

        sepoliaPoolERC1155.enableChain(saigonNetworkDetails.chainSelector, address(saigonPoolERC1155), extraArgs);
        vm.prank(auth);
        AccessControlEnumerable(SEPOLIA_NFT_ERC1155).grantRole(keccak256("MINTER_ROLE"), address(sepoliaPoolERC1155));

        // Step 4) On Ronin Saigon, call enableChain function
        vm.selectFork(saigonFork);
        assertEq(vm.activeFork(), saigonFork);

        saigonPoolERC1155.enableChain(sepoliaNetworkDetails.chainSelector, address(sepoliaPoolERC1155), extraArgs);

        // Step 5) On Ronin Saigon, fund LockReleaseNFTPool.sol with 3 LINK
        assertEq(vm.activeFork(), saigonFork);

        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, 3 ether);

        // Step 6) On Ronin Saigon, mint new ERC1155
        assertEq(vm.activeFork(), saigonFork);

        uint256 id = vm.unixTime();
        vm.prank(auth);
        IERC1155Mintable(RONIN_NFT_ERC1155).mint(alice, id, 100, "");

        vm.startPrank(alice);
        IERC20(saigonNetworkDetails.linkAddress).approve(address(saigonPoolERC1155), 3 ether);
        IERC1155Mintable(RONIN_NFT_ERC1155).setApprovalForAll(address(saigonPoolERC1155), true);

        // Step 7) On Ronin Saigon, crossChainTransfer ERC1155
        saigonPoolERC1155.crossChainTransfer(
            address(bob), id, 100, sepoliaNetworkDetails.chainSelector, ILockReleaseNFTPool.PayFeesIn.LINK
        );

        vm.stopPrank();

        assertEq(
            IERC1155Mintable(RONIN_NFT_ERC1155).balanceOf(address(saigonPoolERC1155), id),
            100,
            "NFT should be locked in the pool"
        );

        // On Ethereum Sepolia, check if ERC1155 was successfully transferred
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork); // THIS LINE REPLACES CHAINLINK CCIP DONs, DO NOT FORGET IT
        assertEq(vm.activeFork(), sepoliaFork);

        assertEq(IERC1155Mintable(SEPOLIA_NFT_ERC1155).balanceOf(bob, id), 100, "NFT should be transferred to Bob");
    }

    function testFork_CanBridge_ERC721_From_Saigon_To_Sepolia_MintWhenIdIsMissing() public {
        // Step 3) On Ethereum Sepolia, call enableChain function
        vm.selectFork(sepoliaFork);
        assertEq(vm.activeFork(), sepoliaFork);

        encodeExtraArgs = new EncodeExtraArgs();

        uint256 gasLimit = 200_000;
        bytes memory extraArgs = encodeExtraArgs.encode(gasLimit);
        assertEq(extraArgs, hex"97a657c90000000000000000000000000000000000000000000000000000000000030d40"); // value taken from https://cll-devrel.gitbook.io/ccip-masterclass-3/ccip-masterclass/exercise-ERC721#step-3-on-ethereum-sepolia-call-enablechain-function

        sepoliaPoolERC721.enableChain(saigonNetworkDetails.chainSelector, address(saigonPoolERC721), extraArgs);

        // Step 4) On Ronin Saigon, call enableChain function
        vm.selectFork(saigonFork);
        assertEq(vm.activeFork(), saigonFork);

        saigonPoolERC721.enableChain(sepoliaNetworkDetails.chainSelector, address(sepoliaPoolERC721), extraArgs);

        // Step 5) On Ronin Saigon, fund LockReleaseNFTPool.sol with 3 LINK
        assertEq(vm.activeFork(), saigonFork);

        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, 3 ether);

        // Step 6) On Ronin Saigon, mint new ERC721
        assertEq(vm.activeFork(), saigonFork);

        uint256 id = vm.unixTime();
        IERC721Mintable(RONIN_NFT_ERC721).mint(alice, id);

        vm.startPrank(alice);
        IERC20(saigonNetworkDetails.linkAddress).approve(address(saigonPoolERC721), 3 ether);
        IERC721Mintable(RONIN_NFT_ERC721).approve(address(saigonPoolERC721), id);

        // Step 7) On Ronin Saigon, crossChainTransfer ERC721
        saigonPoolERC721.crossChainTransfer(
            address(bob), id, 0, sepoliaNetworkDetails.chainSelector, ILockReleaseNFTPool.PayFeesIn.LINK
        );

        vm.stopPrank();

        assertEq(
            IERC721Mintable(RONIN_NFT_ERC721).ownerOf(id), address(saigonPoolERC721), "NFT should be locked in the pool"
        );

        // On Ethereum Sepolia, check if ERC721 was successfully transferred
        ccipLocalSimulatorFork.switchChainAndRouteMessage(sepoliaFork); // THIS LINE REPLACES CHAINLINK CCIP DONs, DO NOT FORGET IT
        assertEq(vm.activeFork(), sepoliaFork);

        assertEq(IERC721Mintable(SEPOLIA_NFT_ERC721).ownerOf(id), bob, "NFT should be transferred to Bob");
    }
}
