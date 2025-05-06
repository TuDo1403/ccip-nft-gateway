// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {Any2EVMAddress} from "src/libraries/Any2EVMAddress.sol";

interface ICCIPSenderReceiver is IAny2EVMMessageReceiver, IERC165 {
    error CursedByRMN();
    error SenderNotEnabled(uint64 chainSelector, Any2EVMAddress sender);
    error OnlyRemoteChain(uint64 chainSelector);
    error OnlyLocalChain(uint64 chainSelector);
    error ZeroAddressNotAllowed();
    error ZeroValueNotAllowed();
    error InvalidRouter(address expected, address actual);
    error NonExistentChain(uint64 chainSelector);
    error ChainAlreadyEnabled(uint64 chainSelector);
    error ChainNotSupported(uint64 chainSelector);
    error MsgValueNotAllowed(uint256 value);
    error RefundFailed(address to, uint256 value);
    error InsufficientAllowance(uint256 expected, uint256 actual);

    struct RemoteChainConfig {
        uint64 _chainSelector;
        Any2EVMAddress _addr;
    }

    event Refunded(address indexed to, uint256 value);
    event MessageSent(address indexed by, bytes32 indexed messageId);
    event MessageReceived(Any2EVMAddress by, bytes32 indexed messageId);

    event RemoteChainDisabled(address indexed by, uint64 indexed chainSelector);
    event RemoteChainEnabled(address indexed by, uint64 indexed chainSelector, Any2EVMAddress addr);
}
