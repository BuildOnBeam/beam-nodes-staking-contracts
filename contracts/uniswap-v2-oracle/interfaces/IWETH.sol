// SPDX-License-Identifier: MIT
/**
 * @notice interface of originally deployed WETH contract on Beam (from uniswap-v2)
 */
pragma solidity >=0.5.0;

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint value) external returns (bool);

    function withdraw(
        uint
    ) external;
}
