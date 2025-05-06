// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

struct Any2EVMAddress {
    bytes _raw;
}

using {raw, toEVM, id, eq, neq, isNull, isNotNull} for Any2EVMAddress global;

function toAny(address self) pure returns (Any2EVMAddress memory) {
    return Any2EVMAddress({_raw: abi.encode(self)});
}

function toEVM(Any2EVMAddress memory self) pure returns (address) {
    return abi.decode(self._raw, (address));
}

function raw(Any2EVMAddress memory self) pure returns (bytes memory) {
    return self._raw;
}

function isNull(Any2EVMAddress memory self) pure returns (bool) {
    return self._raw.length == 0;
}

function isNotNull(Any2EVMAddress memory self) pure returns (bool) {
    return self._raw.length != 0;
}

function id(Any2EVMAddress memory self) pure returns (bytes32) {
    return keccak256(self._raw);
}

function eq(Any2EVMAddress memory self, Any2EVMAddress memory other) pure returns (bool) {
    return id(self) == id(other);
}

function neq(Any2EVMAddress memory self, Any2EVMAddress memory other) pure returns (bool) {
    return id(self) != id(other);
}
