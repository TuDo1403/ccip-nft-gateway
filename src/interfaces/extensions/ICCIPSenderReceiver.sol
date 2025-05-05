// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

interface ICCIPSenderReceiver is IAny2EVMMessageReceiver, IERC165 {
    error CursedByRMN();
    error SenderNotEnabled(uint64 chainSelector, address sender);
    error OnlyOtherChain(uint64 chainSelector);
    error ZeroAddressNotAllowed();
    error InvalidRouter(address expected, address actual);
    error InvalidArmProxy(address expected, address actual);
    error NativeFeeNotAllowed();
    error NonExistentChain(uint64 chainSelector);
    error CallerIsNotARampOnRouter(address caller);
    error ChainNotAllowed(uint64 remoteChainSelector);

    event MessageSent(address indexed by, bytes32 indexed messageId);
    event MessageReceived(address indexed by, bytes32 indexed messageId);
}
