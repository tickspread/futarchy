// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Generic Conditional Token Framework Interface
/// @notice Interface for splitting and merging conditional tokens
interface ICTFAdapter {
    /// @notice Splits collateral tokens into conditional outcome tokens
    /// @param collateralToken The ERC20 token to split
    /// @param conditionId The condition identifier
    /// @param amount Amount of collateral tokens to split
    /// @param outcomeCount Number of outcomes in the condition
    /// @return wrappedTokens Array of ERC20 addresses representing conditional tokens
    function splitCollateralTokens(IERC20 collateralToken, bytes32 conditionId, uint256 amount, uint256 outcomeCount)
        external
        returns (address[] memory wrappedTokens);

    /// @notice Redeems conditional tokens for collateral after condition resolution
    /// @param collateralToken The original ERC20 collateral token
    /// @param conditionId The condition identifier
    /// @param amounts Array of amounts to redeem for each outcome position
    /// @param outcomeCount Number of outcomes in the condition
    /// @return payoutAmount Total amount of collateral tokens received
    function redeemPositions(
        IERC20 collateralToken,
        bytes32 conditionId,
        uint256[] calldata amounts,
        uint256 outcomeCount
    ) external returns (uint256 payoutAmount);

    /// @notice View function to get wrapped token addresses without performing splits
    /// @param collateralToken The ERC20 token that would be split
    /// @param conditionId The condition identifier
    /// @param outcomeCount Number of outcomes in the condition
    /// @return addresses Array of ERC20 addresses for the outcomes
    function getWrappedTokens(IERC20 collateralToken, bytes32 conditionId, uint256 outcomeCount)
        external
        view
        returns (address[] memory addresses);
}
