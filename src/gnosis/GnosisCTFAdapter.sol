// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IConditionalTokens.sol";
import "../interfaces/IWrapped1155Factory.sol";
import "../interfaces/IERC20Extended.sol";

/// @title Gnosis CTF Adapter
/// @author Futarchy Project Team
/// @notice Provides a simplified interface for splitting ERC20 tokens into conditional outcome tokens
/// @dev Integrates with Gnosis Conditional Token Framework (CTF) and Wrapped1155Factory to handle
/// the conversion between ERC20 tokens and conditional tokens. All operations are permissionless.
/// @custom:security-contact security@futarchy.com
contract GnosisCTFAdapter {
    using SafeERC20 for IERC20;

    /// @notice Reference to Gnosis CTF contract
    IConditionalTokens public immutable conditionalTokens;
    /// @notice Reference to the factory that wraps ERC1155 tokens as ERC20
    IWrapped1155Factory public immutable wrapped1155Factory;

    // Custom errors
    /// @notice Thrown when outcome count is invalid (must be > 1)
    error InvalidOutcomeCount(uint256 count);
    /// @notice Thrown when ERC1155 to ERC20 wrapping fails
    error WrappingFailed();
    /// @notice Thrown when position redemption fails
    error RedemptionFailed();
    /// @notice Thrown when condition has not been resolved
    error ConditionNotResolved();

    constructor(address _conditionalTokens, address _wrapped1155Factory) {
        conditionalTokens = IConditionalTokens(_conditionalTokens);
        wrapped1155Factory = IWrapped1155Factory(_wrapped1155Factory);
    }

    // Add the missing function
    function getWrappedTokens(IERC20 collateralToken, bytes32 conditionId, uint256 outcomeCount)
        external
        view
        returns (address[] memory addresses)
    {
        if (outcomeCount <= 1) revert InvalidOutcomeCount(outcomeCount);

        addresses = new address[](outcomeCount);
        uint256[] memory partition = new uint256[](outcomeCount);

        for (uint256 i = 0; i < outcomeCount; i++) {
            partition[i] = 1 << i;

            uint256 positionId = conditionalTokens.getPositionId(
                collateralToken, conditionalTokens.getCollectionId(bytes32(0), conditionId, partition[i])
            );

            bytes memory tokenData = abi.encodePacked(
                _generateTokenName(collateralToken, i, outcomeCount),
                _generateTokenSymbol(collateralToken, i, outcomeCount),
                hex"12"
            );

            addresses[i] =
                address(wrapped1155Factory.getWrapped1155(IERC20(address(conditionalTokens)), positionId, tokenData));
        }

        return addresses;
    }

    function splitCollateralTokens(IERC20 collateralToken, bytes32 conditionId, uint256 amount, uint256 outcomeCount)
        external
        returns (address[] memory wrappedTokens)
    {
        if (outcomeCount <= 1) revert InvalidOutcomeCount(outcomeCount);

        uint256[] memory partition = new uint256[](outcomeCount);
        for (uint256 i = 0; i < outcomeCount; i++) {
            partition[i] = 1 << i;
        }

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        collateralToken.approve(address(conditionalTokens), amount);

        conditionalTokens.splitPosition(collateralToken, bytes32(0), conditionId, partition, amount);

        wrappedTokens = new address[](outcomeCount);
        for (uint256 i = 0; i < outcomeCount; i++) {
            uint256 positionId = conditionalTokens.getPositionId(
                collateralToken, conditionalTokens.getCollectionId(bytes32(0), conditionId, partition[i])
            );

            bytes memory tokenData = abi.encodePacked(
                _generateTokenName(collateralToken, i, outcomeCount),
                _generateTokenSymbol(collateralToken, i, outcomeCount),
                hex"12"
            );

            wrappedTokens[i] = address(
                wrapped1155Factory.requireWrapped1155(IERC20(address(conditionalTokens)), positionId, tokenData)
            );
        }

        return wrappedTokens;
    }

    function redeemPositions(
        IERC20 collateralToken,
        bytes32 conditionId,
        uint256[] calldata amounts,
        uint256 outcomeCount
    ) external returns (uint256 payoutAmount) {
        uint256 payoutDenominator = conditionalTokens.payoutDenominator(conditionId);
        if (payoutDenominator == 0) revert ConditionNotResolved();

        uint256[] memory partition = new uint256[](outcomeCount);
        for (uint256 i = 0; i < outcomeCount; i++) {
            partition[i] = 1 << i;

            if (amounts[i] > 0) {
                uint256 positionId = conditionalTokens.getPositionId(
                    collateralToken, conditionalTokens.getCollectionId(bytes32(0), conditionId, partition[i])
                );

                try wrapped1155Factory.unwrap(
                    IERC20(address(conditionalTokens)), positionId, amounts[i], address(this), ""
                ) { } catch {
                    revert WrappingFailed();
                }
            }
        }

        uint256[] memory indexSets = new uint256[](outcomeCount);
        for (uint256 i = 0; i < outcomeCount; i++) {
            indexSets[i] = partition[i];
        }

        try conditionalTokens.redeemPositions(collateralToken, bytes32(0), conditionId, indexSets) { }
        catch {
            revert RedemptionFailed();
        }

        payoutAmount = collateralToken.balanceOf(address(this));
        if (payoutAmount > 0) {
            collateralToken.safeTransfer(msg.sender, payoutAmount);
        }

        return payoutAmount;
    }

    function _generateTokenName(IERC20 collateralToken, uint256 outcomeIndex, uint256 totalOutcomes)
        internal
        view
        returns (bytes32)
    {
        string memory baseToken = IERC20Extended(address(collateralToken)).name();

        if (totalOutcomes == 2) {
            return outcomeIndex == 1
                ? bytes32(bytes(string.concat(baseToken, " Yes Position")))
                : bytes32(bytes(string.concat(baseToken, " No Position")));
        }

        bytes memory letter = new bytes(1);
        letter[0] = bytes1(uint8(65 + outcomeIndex));

        return bytes32(bytes(string.concat(baseToken, " Outcome ", string(letter))));
    }

    function _generateTokenSymbol(IERC20 collateralToken, uint256 outcomeIndex, uint256 totalOutcomes)
        internal
        view
        returns (bytes32)
    {
        string memory baseSymbol = IERC20Extended(address(collateralToken)).symbol();

        if (totalOutcomes == 2) {
            return outcomeIndex == 1
                ? bytes32(bytes(string.concat(baseSymbol, "-Y")))
                : bytes32(bytes(string.concat(baseSymbol, "-N")));
        }

        bytes memory letter = new bytes(1);
        letter[0] = bytes1(uint8(65 + outcomeIndex));

        return bytes32(bytes(string.concat(baseSymbol, "-", string(letter))));
    }
}
