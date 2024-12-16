// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IBalancerPoolWrapper.sol";

interface IBalancerVault {
    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request)
        external
        payable;

    function exitPool(bytes32 poolId, address sender, address recipient, ExitPoolRequest memory request) external;

    function createPool(
        bytes32 poolId,
        address[] memory tokens,
        uint256[] memory weights,
        address[] memory assetManagers,
        uint256 swapFeePercentage
    ) external returns (address);
}

contract BalancerPoolWrapper {
    using SafeERC20 for IERC20;

    IBalancerVault public immutable vault;

    constructor(address _vault) {
        vault = IBalancerVault(_vault);
    }

    function createPool(address tokenA, address tokenB, uint256 weight) external returns (address pool) {
        require(weight <= 1000000, "Weight must be <= 100%"); // 1000000 = 100%

        // Setup pool parameters
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        uint256[] memory weights = new uint256[](2);
        weights[0] = weight;
        weights[1] = 1000000 - weight;

        address[] memory assetManagers = new address[](2);
        assetManagers[0] = address(0);
        assetManagers[1] = address(0);

        // Create unique poolId
        bytes32 poolId = keccak256(abi.encodePacked(block.timestamp, tokenA, tokenB, msg.sender));

        // Create pool through Balancer
        pool = vault.createPool(
            poolId,
            tokens,
            weights,
            assetManagers,
            3000000000000000 // 0.3% swap fee
        );

        return pool;
    }

    function addLiquidity(address pool, uint256 amountA, uint256 amountB) external returns (uint256 lpAmount) {
        // Get poolId from pool address
        bytes32 poolId; // Need to implement getting poolId from pool address

        address[] memory assets = new address[](2);
        uint256[] memory maxAmountsIn = new uint256[](2);

        // Join pool with exact amounts
        vault.joinPool(
            poolId,
            address(this),
            msg.sender,
            IBalancerVault.JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maxAmountsIn,
                userData: abi.encode(amountA, amountB),
                fromInternalBalance: false
            })
        );

        // Need to get LP amount from pool
        return lpAmount;
    }

    function removeLiquidity(address pool, uint256 lpAmount) external returns (uint256 amountA, uint256 amountB) {
        // Get poolId from pool address
        bytes32 poolId; // Need to implement getting poolId from pool address

        address[] memory assets = new address[](2);
        uint256[] memory minAmountsOut = new uint256[](2);

        // Exit pool with exact LP amount
        vault.exitPool(
            poolId,
            address(this),
            msg.sender,
            IBalancerVault.ExitPoolRequest({
                assets: assets,
                minAmountsOut: minAmountsOut,
                userData: abi.encode(lpAmount),
                toInternalBalance: false
            })
        );

        // Return actual amounts received
        return (amountA, amountB);
    }
}
