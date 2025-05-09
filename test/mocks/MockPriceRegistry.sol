// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MockPriceRegistry {
    address[] internal s_feeTokens;

    function setFeeTokens(address[] memory feeTokens) external {
        s_feeTokens = feeTokens;
    }

    function getFeeTokens() external view returns (address[] memory) {
        return s_feeTokens;
    }
}
