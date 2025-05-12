// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MockPauser {
    address public pauser;
    bool public paused;

    constructor(address _pauser) {
        pauser = _pauser;
    }

    function pause() external {
        require(msg.sender == pauser, "Not pauser");
        paused = true;
    }
    
    function unpause() external {
        require(msg.sender == pauser, "Not pauser");
        paused = false;
    }
}
