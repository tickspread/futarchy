// src/interfaces/IBalancerPoolWrapper.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBalancerPoolWrapper {
    function createPool(address tokenA, address tokenB, uint256 weight) external returns (address pool);

    function addLiquidity(address pool, uint256 amountA, uint256 amountB) external returns (uint256 lpAmount);

    function removeLiquidity(address pool, uint256 lpAmount) external returns (uint256 amountA, uint256 amountB);
}
