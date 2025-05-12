// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MockTokenAdminRegistry {
    struct TokenConfig {
        address administrator; // the current administrator of the token
        address pendingAdministrator; // the address that is pending to become the new administrator
        address tokenPool; // the token pool for this token. Can be address(0) if not deployed or not configured.
    }

    mapping(address token => address admin) public tokenAdmins;
    mapping(address token => address pool) public tokenPools;

    function getTokenConfig(address token) external view returns (TokenConfig memory cfg) {
        cfg.administrator = tokenAdmins[token];
        cfg.tokenPool = tokenPools[token];
    }

    function setTokenAdmin(address token, address admin) external {
        tokenAdmins[token] = admin;
    }

    function setTokenPool(address token, address pool) external {
        tokenPools[token] = pool;
    }
}
