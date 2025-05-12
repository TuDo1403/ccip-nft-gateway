// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MultiLockMintERC721Pool} from "src/pools/erc721/MultiLockMintERC721Pool.sol";
import {MockERC721Mintable} from "test/mocks/MockERC721Mintable.sol";
import {CCIPLocalSimulator} from "test/simulators/CCIPLocalSimulator.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ICCIPSenderReceiver} from "src/interfaces/extensions/ICCIPSenderReceiver.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {ITokenPool} from "src/interfaces/pools/ITokenPool.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ITypeAndVersion} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/ITypeAndVersion.sol";
import {IMultiTokenPool} from "src/interfaces/pools/IMultiTokenPool.sol";
import {IRateLimitConsumer} from "src/interfaces/extensions/IRateLimitConsumer.sol";
import {IPausableExtended} from "src/interfaces/extensions/IPausableExtended.sol";
import {ILockMintERC721Pool} from "src/interfaces/pools/erc721/ILockMintERC721Pool.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IMultiLockMintERC721Pool} from "src/interfaces/pools/erc721/IMultiLockMintERC721Pool.sol";
import {ISharedStorageConsumer} from "src/interfaces/extensions/ISharedStorageConsumer.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MockPauser} from "test/mocks/MockPauser.sol";

contract MultiLockMintERC721Pool_UnitTest is Test {
    using Clones for address;
    using ERC165Checker for address;

    error ReceiverError(bytes4 errSelector);

    address public blueprint;

    MultiLockMintERC721Pool public pool;
    MockERC721Mintable public erc721;
    CCIPLocalSimulator public ccipSimulator;
    uint64 public currentChainSelector = 1;

    UpgradeableBeacon public beacon;
    address public beaconOwner = makeAddr("beaconOwner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public admin = msg.sender;

    uint32 public initFixedGas = 100000;
    uint32 public initDynamicGas = 200000;

    function setUp() public {
        ccipSimulator = new CCIPLocalSimulator();
        beacon = new UpgradeableBeacon(address(new MultiLockMintERC721Pool()), beaconOwner);
        blueprint = address(new BeaconProxy(address(beacon), ""));
        pool = MultiLockMintERC721Pool(blueprint.clone());

        pool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), currentChainSelector);

        assertEq(pool.getGlobalPauser(), admin);
        assertTrue(pool.hasRole(pool.PAUSER_ROLE(), admin));
        (uint32 fixedGas, uint32 dynamicGas) = pool.getGasLimitConfig();
        assertEq(fixedGas, initFixedGas);
        assertEq(dynamicGas, initDynamicGas);
        assertTrue(pool.hasRole(pool.TOKEN_POOL_OWNER_ROLE(), admin));

        targetArtifact("MultiLockMintERC721Pool");
        // targetContract(address(pool));
    }

    function crossTransfer(
        address caller,
        address localToken,
        uint64 remoteChainSelector,
        address to,
        uint256 id,
        address fee,
        uint256 nativeValue,
        bool reverted
    ) public virtual {
        if (!reverted) {
            // vm.expectEmit(address(pool));
            // emit ICCIPSenderReceiver.MessageSent(caller)
        }

        vm.prank(caller);
        pool.crossTransfer{value: nativeValue}(localToken, remoteChainSelector, to, id, fee);

        if (reverted) return;

        assertEq(IERC721(localToken).ownerOf(id), address(pool));
        address remoteToken = pool.getRemoteToken(localToken, remoteChainSelector);
        assertEq(IERC721(remoteToken).ownerOf(id), to);
    }

    function crossBatchTransfer(
        address caller,
        address localToken,
        uint64 remoteChainSelector,
        address to,
        uint256[] memory ids,
        address fee,
        uint256 nativeValue,
        bool reverted
    ) public virtual {
        if (!reverted) {
            // vm.expectEmit(address(pool));
            // emit ICCIPSenderReceiver.MessageSent(caller)
        }

        vm.prank(caller);
        pool.crossBatchTransfer{value: nativeValue}(localToken, remoteChainSelector, to, ids, fee);

        if (reverted) return;

        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(IERC721(localToken).ownerOf(ids[i]), address(pool));
            address remoteToken = pool.getRemoteToken(localToken, remoteChainSelector);
            assertEq(IERC721(remoteToken).ownerOf(ids[i]), to);
        }
    }

    function unmapRemoteToken(address caller, address localToken, uint64 remoteChainSelector, bool reverted)
        public
        virtual
    {
        if (!reverted) {
            vm.expectEmit(address(pool));
            emit ITokenPool.RemoteTokenUnmapped(caller, remoteChainSelector, localToken);
        }

        vm.prank(caller);
        pool.unmapRemoteToken(localToken, remoteChainSelector);

        if (reverted) return;

        assertEq(pool.getRemoteToken(localToken, remoteChainSelector), address(0));

        (address[] memory localTokens,) = pool.getSupportedTokensForChain(remoteChainSelector);
        bool found = false;
        for (uint256 i = 0; i < localTokens.length; i++) {
            if (localTokens[i] == localToken) {
                found = true;
                break;
            }
        }
        assertFalse(found, "Local token found in the list");

        uint64[] memory supportedChains = pool.getSupportedChains();
        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (pool.getRemoteToken(localToken, supportedChains[i]) != address(0)) {
                found = true;
                break;
            }
        }

        if (!found) {
            assertFalse(pool.isSupportedToken(localToken), "Local token should not be supported");
        } else {
            assertTrue(pool.isSupportedToken(localToken), "Local token should be supported");
        }
    }

    function mapRemoteToken(
        address caller,
        address localToken,
        uint64 remoteChainSelector,
        address remoteToken,
        bool reverted
    ) public virtual {
        if (!reverted) {
            vm.expectEmit(address(pool));
            emit ITokenPool.RemoteTokenMapped(caller, remoteChainSelector, localToken, remoteToken);
        }

        vm.prank(caller);
        pool.mapRemoteToken(localToken, remoteChainSelector, remoteToken);

        if (reverted) return;

        assertEq(pool.getRemoteToken(localToken, remoteChainSelector), remoteToken);
        assertTrue(pool.isSupportedToken(localToken));

        (address[] memory localTokens,) = pool.getSupportedTokensForChain(remoteChainSelector);
        bool found = false;
        for (uint256 i = 0; i < localTokens.length; i++) {
            if (localTokens[i] == localToken) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Local token not found in the list");
    }

    function setGasLimitConfig(address caller, uint32 fixedGas, uint32 dynamicGas, bool reverted) public {
        if (!reverted) {
            vm.expectEmit(address(pool));
            emit ITokenPool.GasLimitConfigured(caller, fixedGas, dynamicGas);
        }

        vm.prank(caller);
        pool.setGasLimitConfig(fixedGas, dynamicGas);

        if (reverted) return;

        (uint32 retFixedGas, uint32 retDynamicGas) = pool.getGasLimitConfig();
        assertEq(retFixedGas, fixedGas);
        assertEq(retDynamicGas, dynamicGas);
    }

    function addRemotePool(address caller, uint64 remoteChainSelector, address remotePool, bool reverted) public {
        if (!reverted) {
            vm.expectEmit(address(pool));
            emit ICCIPSenderReceiver.RemoteChainEnabled(caller, remoteChainSelector, remotePool);
            vm.expectEmit(address(pool));
            emit ITokenPool.RemotePoolAdded(caller, remoteChainSelector, remotePool);
        }

        vm.prank(caller);
        pool.addRemotePool(remoteChainSelector, remotePool);

        if (reverted) return;

        uint64[] memory supportedChains = pool.getSupportedChains();
        assertEq(pool.getRemotePool(remoteChainSelector), remotePool);
        assertEq(supportedChains[supportedChains.length - 1], remoteChainSelector);
        assertTrue(pool.isSupportedChain(remoteChainSelector));

        (uint64[] memory remoteChainSelectors, address[] memory remotePools) = pool.getRemotePools();
        bool found = false;
        for (uint256 i = 0; i < remotePools.length; i++) {
            if (remotePools[i] == remotePool && remoteChainSelectors[i] == remoteChainSelector) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Remote pool not found in the list");
    }

    function removeRemotePool(address caller, uint64 remoteChainSelector, address remotePool, bool reverted) public {
        if (!reverted) {
            vm.expectEmit(address(pool));
            emit ICCIPSenderReceiver.RemoteChainDisabled(caller, remoteChainSelector);
            vm.expectEmit(address(pool));
            emit ITokenPool.RemotePoolRemoved(caller, remoteChainSelector);
        }

        vm.prank(caller);
        pool.removeRemotePool(remoteChainSelector);

        if (reverted) return;

        assertEq(pool.getRemotePool(remoteChainSelector), address(0));
        assertFalse(pool.isSupportedChain(remoteChainSelector));

        (uint64[] memory remoteChainSelectors, address[] memory remotePools) = pool.getRemotePools();
        bool found = false;
        for (uint256 i = 0; i < remotePools.length; i++) {
            if (remotePools[i] == remotePool && remoteChainSelectors[i] == remoteChainSelector) {
                found = true;
                break;
            }
        }
        assertFalse(found, "Remote pool found in the list");
    }

    function testConcrete_typeAndVersion() public virtual {
        assertEq(pool.typeAndVersion(), "MultiLockMintERC721Pool 1.0.0");
    }

    function testConcrete_supportsInterface() public virtual {
        assertTrue(
            address(pool).supportsInterface(type(ISharedStorageConsumer).interfaceId),
            "ISharedStorageConsumer not supported"
        );
        assertTrue(
            address(pool).supportsInterface(type(IMultiLockMintERC721Pool).interfaceId),
            "IMultiLockMintERC721Pool not supported"
        );
        assertTrue(
            address(pool).supportsInterface(type(ILockMintERC721Pool).interfaceId), "ILockMintERC721Pool not supported"
        );
        assertTrue(
            address(pool).supportsInterface(type(IRateLimitConsumer).interfaceId), "IRateLimitConsumer not supported"
        );
        assertTrue(
            address(pool).supportsInterface(type(IPausableExtended).interfaceId), "IPausableExtended not supported"
        );
        assertTrue(address(pool).supportsInterface(type(ITypeAndVersion).interfaceId), "ITypeAndVersion not supported");
        assertTrue(address(pool).supportsInterface(type(IMultiTokenPool).interfaceId), "IMultiTokenPool not supported");
        assertTrue(address(pool).supportsInterface(type(ITokenPool).interfaceId), "ITokenPool not supported");

        assertTrue(
            address(pool).supportsInterface(type(IAny2EVMMessageReceiver).interfaceId),
            "IAny2EVMMessageReceiver not supported"
        );
        assertTrue(
            address(pool).supportsInterface(type(ICCIPSenderReceiver).interfaceId), "ICCIPSenderReceiver not supported"
        );
        assertTrue(address(pool).supportsInterface(type(IERC165).interfaceId), "IERC165 not supported");
        assertTrue(
            address(pool).supportsInterface(type(IAccessControlEnumerable).interfaceId),
            "IAccessControlEnumerable not supported"
        );
        assertTrue(address(pool).supportsInterface(type(IAccessControl).interfaceId), "IAccessControl not supported");
    }

    function testConcrete_RevertIf_Unauthorized_withdrawLiquidity() external {
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        address remoteToken = makeAddr("remoteToken");
        address to = makeAddr("to");
        uint64 remoteChainSelector = 2;

        ccipSimulator.supportChain(remoteChainSelector);

        vm.startPrank(admin);
        pool.addRemotePool(remoteChainSelector, makeAddr("remotePool"));
        pool.mapRemoteToken(address(localToken), remoteChainSelector, remoteToken);
        vm.stopPrank();

        localToken.mint(address(pool), 1);
        localToken.mint(address(pool), 2);
        localToken.mint(address(pool), 3);

        address[] memory localTokens = new address[](3);
        localTokens[0] = address(localToken);
        localTokens[1] = address(localToken);
        localTokens[2] = address(localToken);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        address[] memory tos = new address[](3);
        tos[0] = to;
        tos[1] = to;
        tos[2] = to;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), pool.DEFAULT_ADMIN_ROLE()
            )
        );
        pool.withdrawLiquidity(localTokens, tos, ids);
    }

    function testConcrete_Admin_withdrawalLiquidity() external {
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        address remoteToken = makeAddr("remoteToken");
        address to = makeAddr("to");
        uint64 remoteChainSelector = 2;

        ccipSimulator.supportChain(remoteChainSelector);

        vm.startPrank(admin);
        pool.addRemotePool(remoteChainSelector, makeAddr("remotePool"));
        pool.mapRemoteToken(address(localToken), remoteChainSelector, remoteToken);
        vm.stopPrank();

        localToken.mint(address(pool), 1);
        localToken.mint(address(pool), 2);
        localToken.mint(address(pool), 3);

        address[] memory localTokens = new address[](3);
        localTokens[0] = address(localToken);
        localTokens[1] = address(localToken);
        localTokens[2] = address(localToken);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        address[] memory tos = new address[](3);
        tos[0] = to;
        tos[1] = to;
        tos[2] = to;

        vm.prank(admin);
        pool.withdrawLiquidity(localTokens, tos, ids);

        assertEq(localToken.ownerOf(1), to);
        assertEq(localToken.ownerOf(2), to);
        assertEq(localToken.ownerOf(3), to);
    }

    function testFuzz_removeRemotePool(uint64 remoteChainSelector, address remotePool) public {
        vm.assume(remoteChainSelector != currentChainSelector);
        vm.assume(remotePool != address(0));

        ccipSimulator.supportChain(remoteChainSelector);
        addRemotePool(admin, remoteChainSelector, remotePool, false);

        removeRemotePool(admin, remoteChainSelector, remotePool, false);
    }

    function testFuzz_addRemotePool(uint64 remoteChainSelector, address remotePool) public {
        vm.assume(remoteChainSelector != currentChainSelector);
        vm.assume(remotePool != address(0));

        ccipSimulator.supportChain(remoteChainSelector);

        addRemotePool(admin, remoteChainSelector, remotePool, false);
    }

    function testFuzz_mapRemoteToken(address localToken, uint64 remoteChainSelector, address remoteToken) public {
        vm.assume(remoteChainSelector != currentChainSelector);
        vm.assume(localToken != address(0));
        vm.assume(remoteToken != address(0));

        ccipSimulator.supportChain(remoteChainSelector);
        addRemotePool(admin, remoteChainSelector, makeAddr("remotePool"), false);
        mapRemoteToken(admin, localToken, remoteChainSelector, remoteToken, false);
    }

    function testFuzz_crossTransfer(
        address caller,
        uint64 remoteChainSelector,
        address to,
        uint256 id,
        bool nativeFeeOrERC20
    ) public {
        vm.assume(caller != address(0));
        vm.assume(remoteChainSelector != 0);
        vm.assume(remoteChainSelector != currentChainSelector);
        vm.assume(to != address(0));

        ccipSimulator.supportChain(currentChainSelector);
        ccipSimulator.supportChain(remoteChainSelector);

        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        address feeToken = nativeFeeOrERC20 ? address(0) : address(new MockERC20());
        uint256 fee = pool.estimateFee(feeToken, remoteChainSelector, 1);
        uint256 nativeValue = feeToken == address(0) ? fee : 0;
        if (feeToken == address(0)) {
            deal(caller, fee);
        } else {
            deal(feeToken, caller, fee);
            vm.prank(caller);
            IERC20(feeToken).approve(address(pool), fee);
        }

        localToken.mint(caller, id);
        vm.startPrank(caller);
        localToken.approve(address(pool), id);
        vm.stopPrank();

        ccipSimulator.switchChain(currentChainSelector);
        crossTransfer(caller, address(localToken), remoteChainSelector, to, id, feeToken, nativeValue, false);
    }

    function testFuzz_crossBatchTransfer(
        address caller,
        uint64 remoteChainSelector,
        address to,
        uint256[] memory ids,
        bool nativeFeeOrERC20
    ) public {
        vm.assume(!containsDuplicate(ids));
        vm.assume(caller != address(0));
        vm.assume(remoteChainSelector != 0);
        vm.assume(remoteChainSelector != currentChainSelector);
        vm.assume(to != address(0));
        vm.assume(ids.length > 0);

        ccipSimulator.supportChain(currentChainSelector);
        ccipSimulator.supportChain(remoteChainSelector);

        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");
        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        address feeToken = nativeFeeOrERC20 ? address(0) : address(new MockERC20());
        uint256 fee = pool.estimateFee(feeToken, remoteChainSelector, ids.length);
        uint256 nativeValue = feeToken == address(0) ? fee : 0;
        if (feeToken == address(0)) {
            deal(caller, fee);
        } else {
            deal(feeToken, caller, fee);
            vm.prank(caller);
            IERC20(feeToken).approve(address(pool), fee);
        }

        for (uint256 i = 0; i < ids.length; i++) {
            localToken.mint(caller, ids[i]);
        }

        vm.startPrank(caller);
        localToken.setApprovalForAll(address(pool), true);
        vm.stopPrank();

        ccipSimulator.switchChain(currentChainSelector);
        crossBatchTransfer(caller, address(localToken), remoteChainSelector, to, ids, feeToken, nativeValue, false);
    }

    function testConcrete_CanRelease_WhenContainsId_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        uint256 fee = 10 ether;
        deal(caller, fee);

        localToken.mint(caller, 1);
        remoteToken.mint(address(remotePool), 1);

        vm.prank(caller);
        localToken.approve(address(pool), 1);

        ccipSimulator.switchChain(currentChainSelector);
        crossTransfer(caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee, false);
    }

    function testConcrete_CanUseExternalStorage_WhenExternalStorageApproved_ToTransfer_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        uint256 fee = 10 ether;
        deal(caller, fee);

        address sharedStorage = makeAddr("sharedStorage");
        remoteToken.mint(sharedStorage, 1);
        vm.prank(sharedStorage);
        remoteToken.setApprovalForAll(address(remotePool), true);
        vm.prank(admin);
        remotePool.setSharedStorage(sharedStorage, true);

        localToken.mint(caller, 1);

        vm.prank(caller);
        localToken.approve(address(pool), 1);

        ccipSimulator.switchChain(currentChainSelector);
        crossTransfer(caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee, false);
    }

    function testConcrete_RevertIf_FeeIsERC20_SendNativeValue_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(new MockERC20());
        uint64 remoteChainSelector = 2;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        uint256 fee = 10 ether;
        deal(caller, fee);

        localToken.mint(caller, 1);
        vm.prank(caller);
        localToken.approve(address(pool), 1);

        ccipSimulator.switchChain(currentChainSelector);
        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.MsgValueNotAllowed.selector, fee));
        crossTransfer(caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee, true);
    }

    function testConcrete_RefundIf_SendMoreNativeFee_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        uint256 fee = 10 ether;
        deal(caller, fee + 1 ether);

        localToken.mint(caller, 1);
        vm.prank(caller);
        localToken.approve(address(pool), 1);

        ccipSimulator.switchChain(currentChainSelector);
        crossTransfer(
            caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee + 1 ether, false
        );

        assertEq(caller.balance, 1 ether);
    }

    function testConcrete_RevertIf_ExternalStorageNotApproved_ToTransfer_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        uint256 fee = 10 ether;
        deal(caller, fee);

        address sharedStorage = makeAddr("sharedStorage");
        remoteToken.mint(sharedStorage, 1);
        vm.prank(admin);
        remotePool.setSharedStorage(sharedStorage, true);

        localToken.mint(caller, 1);

        vm.prank(caller);
        localToken.approve(address(pool), 1);

        ccipSimulator.switchChain(currentChainSelector);
        vm.expectRevert();
        crossTransfer(caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee, true);
    }

    function testConcrete_RevertIf_PoolIsPaused_ByPauser_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        uint256 fee = 10 ether;
        deal(caller, fee);

        localToken.mint(caller, 1);
        vm.prank(caller);
        localToken.approve(address(pool), 1);

        vm.prank(admin);
        pool.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        crossTransfer(caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee, true);
    }

    function testConcrete_RevertIf_RemotePoolIsPaused_ByPauser_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        uint256 fee = 10 ether;
        deal(caller, fee);

        localToken.mint(caller, 1);
        vm.prank(caller);
        localToken.approve(address(pool), 1);

        vm.prank(admin);
        remotePool.pause();

        ccipSimulator.switchChain(currentChainSelector);
        vm.expectRevert();
        crossTransfer(caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee, true);
    }

    function testConcrete_RevertIf_PoolIsPaused_ByGlobalPauser_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        uint256 fee = 10 ether;
        deal(caller, fee);

        localToken.mint(caller, 1);
        vm.prank(caller);
        localToken.approve(address(pool), 1);

        address emergencyPauser = makeAddr("emergencyPauser");
        MockPauser pauser = new MockPauser(emergencyPauser);
        vm.prank(admin);
        pool.setGlobalPauser(address(pauser));
        vm.prank(emergencyPauser);
        pauser.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        crossTransfer(caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee, true);
    }

    function testConcrete_RevertIf_TokenUnmappedOnCurrentChain_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        uint64 otherRemoteChainSelector = 3;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);
        ccipSimulator.supportChain(otherRemoteChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        addRemotePool(admin, otherRemoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);
        mapRemoteToken(admin, makeAddr("otherLocalToken"), remoteChainSelector, makeAddr("otherRemoteToken"), false);
        mapRemoteToken(admin, address(localToken), otherRemoteChainSelector, address(remoteToken), false);
        unmapRemoteToken(admin, address(localToken), remoteChainSelector, false);

        uint256 fee = 10 ether;
        deal(caller, fee);

        localToken.mint(caller, 1);
        vm.prank(caller);
        localToken.approve(address(pool), 1);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.ZeroAddressNotAllowed.selector));
        crossTransfer(caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee, true);
    }

    function testConcrete_RevertIf_TokenUnmappedOnRemoteChain_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        uint64 otherRemoteChainSelector = 3;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);
        ccipSimulator.supportChain(otherRemoteChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        addRemotePool(admin, otherRemoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);
        mapRemoteToken(admin, address(localToken), otherRemoteChainSelector, address(remoteToken), false);
        assertEq(pool.getRemoteToken(address(localToken), remoteChainSelector), address(remoteToken));

        // Unmap token on remote chain
        vm.startPrank(admin);
        // Map other data to keep local tokens storage not wiped fully
        remotePool.addRemotePool(otherRemoteChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), otherRemoteChainSelector, address(localToken));

        remotePool.unmapRemoteToken(address(remoteToken), currentChainSelector);
        vm.stopPrank();

        assertEq(remotePool.getRemoteToken(address(remoteToken), currentChainSelector), address(0));

        uint256 fee = 10 ether;
        deal(caller, fee);

        localToken.mint(caller, 1);
        vm.prank(caller);
        localToken.approve(address(pool), 1);

        ccipSimulator.switchChain(currentChainSelector);
        vm.expectRevert();
        crossTransfer(caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee, true);
    }

    function testConcrete_RevertIf_ChainNotEnabledOnCurrentChain_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        // disable chain
        removeRemotePool(admin, remoteChainSelector, address(remotePool), false);

        uint256 fee = 10 ether;
        deal(caller, fee);

        localToken.mint(caller, 1);

        vm.expectRevert(abi.encodeWithSelector(IMultiTokenPool.OnlyLocalToken.selector));
        crossTransfer(caller, address(localToken), remoteChainSelector, makeAddr("to"), 1, feeToken, fee, true);
    }

    function testConcrete_RevertIf_ChainNotEnabledOnRemoteChain_crossTransfer() external {
        address caller = makeAddr("caller");
        address feeToken = address(0);
        uint64 remoteChainSelector = 2;
        MockERC721Mintable localToken = new MockERC721Mintable("MockLocal", "MCKL");
        MockERC721Mintable remoteToken = new MockERC721Mintable("MockRemote", "MCKR");

        ccipSimulator.supportChain(remoteChainSelector);
        ccipSimulator.supportChain(currentChainSelector);

        MultiLockMintERC721Pool remotePool = MultiLockMintERC721Pool(blueprint.clone());
        vm.label(address(remotePool), "remotePool");
        remotePool.initialize(admin, initFixedGas, initDynamicGas, address(ccipSimulator.router()), remoteChainSelector);
        vm.startPrank(admin);
        remotePool.addRemotePool(currentChainSelector, address(pool));
        remotePool.mapRemoteToken(address(remoteToken), currentChainSelector, address(localToken));
        vm.stopPrank();

        addRemotePool(admin, remoteChainSelector, address(remotePool), false);
        mapRemoteToken(admin, address(localToken), remoteChainSelector, address(remoteToken), false);

        // disable chain on remote pool
        vm.prank(admin);
        remotePool.removeRemotePool(currentChainSelector);

        uint256 fee = 10 ether;
        deal(caller, fee);

        localToken.mint(caller, 1);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.NonExistentChain.selector, currentChainSelector));
        crossTransfer(caller, address(localToken), currentChainSelector, makeAddr("to"), 1, feeToken, fee, true);
    }

    function testConcrete_ReturnZero_WhenChainDisabled_getRemoteToken() external {
        uint64 remoteChainSelector = 2;
        address localToken = makeAddr("localToken");
        address remoteToken = makeAddr("remoteToken");

        ccipSimulator.supportChain(remoteChainSelector);
        addRemotePool(admin, remoteChainSelector, makeAddr("remotePool"), false);
        mapRemoteToken(admin, localToken, remoteChainSelector, remoteToken, false);

        removeRemotePool(admin, remoteChainSelector, makeAddr("remotePool"), false);

        assertEq(pool.getRemoteToken(localToken, remoteChainSelector), address(0));
    }

    function testConcrete_ReturnZero_WhenChainDisabled_getSupportedTokensForChain() external {
        uint64 remoteChainSelector = 2;
        address localToken = makeAddr("localToken");
        address remoteToken = makeAddr("remoteToken");

        ccipSimulator.supportChain(remoteChainSelector);
        addRemotePool(admin, remoteChainSelector, makeAddr("remotePool"), false);
        mapRemoteToken(admin, localToken, remoteChainSelector, remoteToken, false);

        removeRemotePool(admin, remoteChainSelector, makeAddr("remotePool"), false);

        (address[] memory localTokens,) = pool.getSupportedTokensForChain(remoteChainSelector);
        assertEq(localTokens.length, 0);
    }

    function testConcrete_AllTokensMappedToRemoteChain_IsNotSupported_WhenChainDisabled_isSupportedToken() external {
        uint64 remoteChainSelector = 2;
        ccipSimulator.supportChain(remoteChainSelector);

        address remotePool = makeAddr("remotePool");
        addRemotePool(admin, remoteChainSelector, remotePool, false);

        address localToken1 = makeAddr("localToken1");
        address remoteToken1 = makeAddr("remoteToken1");
        mapRemoteToken(admin, localToken1, remoteChainSelector, remoteToken1, false);
        address localToken2 = makeAddr("localToken2");
        address remoteToken2 = makeAddr("remoteToken2");
        mapRemoteToken(admin, localToken2, remoteChainSelector, remoteToken2, false);
        address localToken3 = makeAddr("localToken3");
        address remoteToken3 = makeAddr("remoteToken3");
        mapRemoteToken(admin, localToken3, remoteChainSelector, remoteToken3, false);

        removeRemotePool(admin, remoteChainSelector, remotePool, false);

        assertFalse(pool.isSupportedToken(localToken1), "Local token 1 should be supported");
        assertFalse(pool.isSupportedToken(localToken2), "Local token 2 should be supported");
        assertFalse(pool.isSupportedToken(localToken3), "Local token 3 should be supported");
    }

    function testConcrete_TokenRemovedFromSet_WhenDisabledAllMappedChain_getTokens() external {
        uint64 remoteChainSelector1 = 2;
        uint64 remoteChainSelector2 = 3;
        uint64 remoteChainSelector3 = 4;
        ccipSimulator.supportChain(remoteChainSelector1);
        ccipSimulator.supportChain(remoteChainSelector2);
        ccipSimulator.supportChain(remoteChainSelector3);

        address remotePool1 = makeAddr("remotePool1");
        addRemotePool(admin, remoteChainSelector1, remotePool1, false);
        address remotePool2 = makeAddr("remotePool2");
        addRemotePool(admin, remoteChainSelector2, remotePool2, false);
        address remotePool3 = makeAddr("remotePool3");
        addRemotePool(admin, remoteChainSelector3, remotePool3, false);

        address localToken = makeAddr("localToken");
        address remoteToken1 = makeAddr("remoteToken1");
        mapRemoteToken(admin, localToken, remoteChainSelector1, remoteToken1, false);
        address remoteToken2 = makeAddr("remoteToken2");
        mapRemoteToken(admin, localToken, remoteChainSelector2, remoteToken2, false);
        address remoteToken3 = makeAddr("remoteToken3");
        mapRemoteToken(admin, localToken, remoteChainSelector3, remoteToken3, false);

        removeRemotePool(admin, remoteChainSelector1, remotePool1, false);
        removeRemotePool(admin, remoteChainSelector2, remotePool2, false);
        removeRemotePool(admin, remoteChainSelector3, remotePool3, false);

        address[] memory localTokens = pool.getTokens();
        bool found = false;
        for (uint256 i = 0; i < localTokens.length; i++) {
            if (localTokens[i] == localToken) {
                found = true;
                break;
            }
        }
        assertFalse(found, "Local token should not be supported");
    }

    function testConcrete_TokensStillInSet_WhenDisabledSomeMappedChain_getTokens() external {
        uint64 remoteChainSelector1 = 2;
        uint64 remoteChainSelector2 = 3;
        uint64 remoteChainSelector3 = 4;
        ccipSimulator.supportChain(remoteChainSelector1);
        ccipSimulator.supportChain(remoteChainSelector2);
        ccipSimulator.supportChain(remoteChainSelector3);

        address remotePool1 = makeAddr("remotePool1");
        addRemotePool(admin, remoteChainSelector1, remotePool1, false);
        address remotePool2 = makeAddr("remotePool2");
        addRemotePool(admin, remoteChainSelector2, remotePool2, false);
        address remotePool3 = makeAddr("remotePool3");
        addRemotePool(admin, remoteChainSelector3, remotePool3, false);

        address localToken = makeAddr("localToken");
        address remoteToken1 = makeAddr("remoteToken1");
        mapRemoteToken(admin, localToken, remoteChainSelector1, remoteToken1, false);
        address remoteToken2 = makeAddr("remoteToken2");
        mapRemoteToken(admin, localToken, remoteChainSelector2, remoteToken2, false);
        address remoteToken3 = makeAddr("remoteToken3");
        mapRemoteToken(admin, localToken, remoteChainSelector3, remoteToken3, false);

        removeRemotePool(admin, remoteChainSelector1, remotePool1, false);
        removeRemotePool(admin, remoteChainSelector2, remotePool2, false);

        address[] memory localTokens = pool.getTokens();
        bool found = false;
        for (uint256 i = 0; i < localTokens.length; i++) {
            if (localTokens[i] == localToken) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Local token should be supported");
    }

    function testConcrete_RevertIf_UnmapUnexistingToken_unmapRemoteToken() external {
        uint64 remoteChainSelector = 2;
        address localToken = makeAddr("localToken");

        ccipSimulator.supportChain(remoteChainSelector);
        addRemotePool(admin, remoteChainSelector, makeAddr("remotePool"), false);

        vm.expectRevert(
            abi.encodeWithSelector(IMultiTokenPool.TokenNotMapped.selector, localToken, remoteChainSelector)
        );
        unmapRemoteToken(admin, localToken, remoteChainSelector, true);
    }

    function testConcrete_CanMapManyTokens_WithSameRemoteChainSelector_mapRemoteToken() external {
        uint64 remoteChainSelector = 2;
        ccipSimulator.supportChain(remoteChainSelector);

        address remotePool = makeAddr("remotePool");
        addRemotePool(admin, remoteChainSelector, remotePool, false);

        address localToken = makeAddr("localToken");
        address remoteToken = makeAddr("remoteToken");
        mapRemoteToken(admin, localToken, remoteChainSelector, remoteToken, false);

        address localToken2 = makeAddr("localToken2");
        address remoteToken2 = makeAddr("remoteToken2");
        mapRemoteToken(admin, localToken2, remoteChainSelector, remoteToken2, false);
    }

    function testConcrete_CanMapManyRemoteTokens_WithSameLocalToken_mapRemoteToken() external {
        uint64 remoteChainSelector = 2;
        ccipSimulator.supportChain(remoteChainSelector);

        address remotePool = makeAddr("remotePool");
        addRemotePool(admin, remoteChainSelector, remotePool, false);

        address localToken = makeAddr("localToken");
        address remoteToken = makeAddr("remoteToken");
        mapRemoteToken(admin, localToken, remoteChainSelector, remoteToken, false);

        uint64 remoteChainSelector2 = 3;
        ccipSimulator.supportChain(remoteChainSelector2);
        address remotePool2 = makeAddr("remotePool2");
        addRemotePool(admin, remoteChainSelector2, remotePool2, false);

        address localToken2 = makeAddr("localToken");
        address remoteToken2 = makeAddr("remoteToken2");
        mapRemoteToken(admin, localToken2, remoteChainSelector2, remoteToken2, false);
    }

    function testConcrete_RevertIf_MapTheSameRemoteToken_ToMany_LocalTokens_InSameRemoteChainSelector_mapRemoteToken()
        external
    {
        uint64 remoteChainSelector = 2;
        ccipSimulator.supportChain(remoteChainSelector);

        address remotePool = makeAddr("remotePool");
        addRemotePool(admin, remoteChainSelector, remotePool, false);

        address localToken = makeAddr("localToken");
        address remoteToken = makeAddr("remoteToken");
        mapRemoteToken(admin, localToken, remoteChainSelector, remoteToken, false);

        address localToken2 = makeAddr("localToken2");
        vm.expectRevert(abi.encodeWithSelector(IMultiTokenPool.TokenAlreadyMapped.selector, localToken, remoteToken));
        mapRemoteToken(admin, localToken2, remoteChainSelector, remoteToken, true);
    }

    function testConcrete_RevertIf_RemotePoolNotAdded_mapRemoteToken() external {
        uint64 remoteChainSelector = 2;
        address localToken = makeAddr("localToken");
        address remoteToken = makeAddr("remoteToken");
        ccipSimulator.supportChain(remoteChainSelector);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.NonExistentChain.selector, remoteChainSelector));
        mapRemoteToken(admin, localToken, remoteChainSelector, remoteToken, true);
    }

    function testConcrete_RevertIf_Unauthorized_mapRemoteToken() external {
        uint64 remoteChainSelector = 2;
        address remotePool = makeAddr("remotePool");
        ccipSimulator.supportChain(remoteChainSelector);
        address any = makeAddr("any");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, any, pool.TOKEN_POOL_OWNER_ROLE()
            )
        );
        mapRemoteToken(any, address(erc721), remoteChainSelector, remotePool, true);
    }

    function testConcrete_RevertIf_MapZeroAddress_mapRemoteToken() external {
        uint64 remoteChainSelector = 2;
        address remotePool = makeAddr("remotePool");
        address remoteToken = makeAddr("remoteToken");
        address localToken = makeAddr("localToken");

        ccipSimulator.supportChain(remoteChainSelector);

        addRemotePool(admin, remoteChainSelector, remotePool, false);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.ZeroAddressNotAllowed.selector));
        mapRemoteToken(admin, address(0), remoteChainSelector, remoteToken, true);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.ZeroAddressNotAllowed.selector));
        mapRemoteToken(admin, localToken, remoteChainSelector, address(0), true);
    }

    function testConcrete_RevertIf_ZeroValue_setGasLimitConfig() external {
        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.ZeroValueNotAllowed.selector));
        setGasLimitConfig(admin, 0, 0, true);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.ZeroValueNotAllowed.selector));
        setGasLimitConfig(admin, 1, 0, true);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.ZeroValueNotAllowed.selector));
        setGasLimitConfig(admin, 0, 2, true);
    }

    function testConcrete_RevertIf_Unauthorized_setGasLimitConfig() external {
        uint32 fixedGas = 100000;
        uint32 dynamicGas = 200000;
        address any = makeAddr("any");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, any, pool.TOKEN_POOL_OWNER_ROLE()
            )
        );
        setGasLimitConfig(any, fixedGas, dynamicGas, true);
    }

    function testConcrete_RevertIf_Unauthorized_addRemotePool() external {
        uint64 remoteChainSelector = 2;
        address remotePool = makeAddr("remotePool");
        ccipSimulator.supportChain(remoteChainSelector);
        address any = makeAddr("any");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, any, pool.TOKEN_POOL_OWNER_ROLE()
            )
        );
        addRemotePool(any, remoteChainSelector, remotePool, true);
    }

    function testConcrete_RevertIf_Unauthorized_removeRemotePool() external {
        uint64 remoteChainSelector = 2;
        address remotePool = makeAddr("remotePool");
        ccipSimulator.supportChain(remoteChainSelector);
        address any = makeAddr("any");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, any, pool.TOKEN_POOL_OWNER_ROLE()
            )
        );
        removeRemotePool(any, remoteChainSelector, remotePool, true);
    }

    function testConcrete_RevertIf_ReAdd_addRemotePool() external {
        uint64 remoteChainSelector = 2;
        address remotePool = makeAddr("remotePool");
        ccipSimulator.supportChain(remoteChainSelector);

        addRemotePool(admin, remoteChainSelector, remotePool, false);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.ChainAlreadyEnabled.selector, remoteChainSelector));
        addRemotePool(admin, remoteChainSelector, remotePool, true);

        address remotePool2 = makeAddr("remotePool2");
        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.ChainAlreadyEnabled.selector, remoteChainSelector));
        addRemotePool(admin, remoteChainSelector, remotePool2, true);
    }

    function testConcrete_RevertIf_ReRemove_removeRemotePool() external {
        uint64 remoteChainSelector = 2;
        address remotePool = makeAddr("remotePool");
        ccipSimulator.supportChain(remoteChainSelector);

        addRemotePool(admin, remoteChainSelector, remotePool, false);

        removeRemotePool(admin, remoteChainSelector, remotePool, false);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.NonExistentChain.selector, remoteChainSelector));
        removeRemotePool(admin, remoteChainSelector, remotePool, true);
    }

    function testConcrete_RevertIf_AddZeroAddress_addRemotePool() external {
        uint64 remoteChainSelector = 2;
        address remotePool = address(0);
        ccipSimulator.supportChain(remoteChainSelector);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.ZeroAddressNotAllowed.selector));
        addRemotePool(admin, remoteChainSelector, remotePool, true);
    }

    function testConcrete_RevertIf_RemoteChainSelectorIsCurrentChainSelector_addRemotePool() external {
        uint64 remoteChainSelector = currentChainSelector;
        address remotePool = makeAddr("remotePool");
        ccipSimulator.supportChain(remoteChainSelector);

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.OnlyRemoteChain.selector, remoteChainSelector));
        addRemotePool(admin, remoteChainSelector, remotePool, true);
    }

    function testConcrete_RevertIf_RemoteChainIsNotSupported_addRemotePool() external {
        uint64 remoteChainSelector = 2;
        address remotePool = makeAddr("remotePool");

        vm.expectRevert(abi.encodeWithSelector(ICCIPSenderReceiver.ChainNotSupported.selector, remoteChainSelector));
        addRemotePool(admin, remoteChainSelector, remotePool, true);
    }

    function containsDuplicate(uint256[] memory array) internal pure returns (bool) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (array[i] == array[j]) {
                    return true;
                }
            }
        }
        return false;
    }
}
