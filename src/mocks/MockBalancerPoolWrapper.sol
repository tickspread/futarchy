// src/mocks/MockBalancerPoolWrapper.sol
pragma solidity ^0.8.20;

import "../interfaces/IBalancerPoolWrapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockBalancerPoolWrapper is IBalancerPoolWrapper {
    uint256 private _nextPoolId = 1;

    struct PoolInfo {
        address tokenA;
        address tokenB;
        // Track liquidity in a simple manner
        uint256 totalLiquidity;
    }

    mapping(address => PoolInfo) public pools;
    mapping(address => uint256) public balancesTokenA;
    mapping(address => uint256) public balancesTokenB;

    function createPool(address tokenA, address tokenB, uint256 /*weight*/ ) external returns (address pool) {
        pool = address(uint160(_nextPoolId++));
        pools[pool] = PoolInfo({ tokenA: tokenA, tokenB: tokenB, totalLiquidity: 0 });

        return pool;
    }

    function addLiquidity(address pool, uint256 amountA, uint256 amountB) external returns (uint256 lpAmount) {
        PoolInfo memory p = pools[pool];

        // Transfer tokens from FutarchyPoolManager to this contract
        IERC20(p.tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(p.tokenB).transferFrom(msg.sender, address(this), amountB);

        uint256 mintedLP = amountA + amountB; // Simplified LP logic
        pools[pool].totalLiquidity += mintedLP;

        return mintedLP;
    }

    function removeLiquidity(address pool, uint256 lpAmount) external returns (uint256 amountA, uint256 amountB) {
        PoolInfo memory p = pools[pool];

        // Simplified calculation: half-half
        amountA = lpAmount / 2;
        amountB = lpAmount / 2;

        // Since the wrapper holds the tokens, transfer them back to the caller
        // Ensure that you have enough tokens in the wrapper contract.
        // In a real scenario, you'd track who owns what portion of the LP,
        // but here we just simulate the scenario as per the test's expectations.
        IERC20(p.tokenA).transfer(msg.sender, amountA);
        IERC20(p.tokenB).transfer(msg.sender, amountB);

        pools[pool].totalLiquidity -= lpAmount;

        return (amountA, amountB);
    }
}
