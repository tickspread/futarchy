// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ExpressionContract.sol";
import "./EventContract.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PositionTokenContract
 * @notice Manages positions tied to expressions with ERC20 collateral
 */
contract PositionTokenContract is ERC1155 {
    using SafeERC20 for IERC20;
    using ExpressionEvaluatorLib for uint256[][];

    uint256 private constant SCALE = 1e18;

    struct Position {
        IERC20 collateralToken;
        uint256 expressionId;
        uint256 evaluatedValue; // Cached evaluation result (0 if not evaluated)
        uint256 evaluationTime; // When the position was evaluated (0 if not evaluated)
    }

    ExpressionContract public immutable expressionContract;
    EventContract public immutable eventContract;
    mapping(uint256 => Position) public positions; // positionId => Position

    event PositionCreated(
        uint256 indexed positionId, uint256 indexed expressionId, address indexed collateralToken, uint256 amount
    );
    event PositionRedeemed(
        uint256 indexed positionId,
        uint256 indexed expressionId,
        address indexed collateralToken,
        uint256 amount,
        uint256 payout
    );
    event PositionEvaluated(uint256 indexed positionId, uint256 indexed expressionId, uint256 value, uint256 timestamp);
    event PositionPartiallyEvaluated(
        uint256 indexed positionId, uint256 indexed variableId, uint256 settledValue, uint256 timestamp
    );

    error ExpressionNotFound();
    error CollateralTransferFailed();
    error CollateralMismatch();
    error NoBalanceToRedeem();
    error NoBalanceToSplit();
    error NoBalanceToMerge();
    error NoBalanceToEvaluate();
    error EvaluationTooComplex();
    error EventsNotSettled();
    error InvalidAmount();
    error PositionNotFound();
    error InvalidSettledValue(uint256 value);

    constructor(address _expressionContract, address _eventContract, string memory uri) ERC1155(uri) {
        expressionContract = ExpressionContract(_expressionContract);
        eventContract = EventContract(_eventContract);
    }

    /**
     * @notice Generates a unique position ID from collateral token and expression
     */
    function getPositionId(IERC20 collateralToken, uint256 expressionId) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralToken, expressionId)));
    }

    /**
     * @notice Creates a new position backed by ERC20 collateral
     */
    function createPosition(IERC20 collateralToken, uint256 amount) external {
        // Newly created positions always associated with the TRUE expression
        uint256 expressionId = 1;
        if (amount == 0) revert InvalidAmount();
        if (!expressionContract.expressionExists(expressionId)) revert ExpressionNotFound();

        uint256 positionId = getPositionId(collateralToken, expressionId);

        // Transfer collateral
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        // Initialize position if not exists
        Position storage pos = positions[positionId];
        if (pos.collateralToken == IERC20(address(0))) {
            pos.collateralToken = collateralToken;
            pos.expressionId = expressionId;
        }

        // Mint position tokens
        _mint(msg.sender, positionId, amount, "");

        emit PositionCreated(positionId, expressionId, address(collateralToken), amount);
    }

    /**
     * @notice Partitions a position into multiple positions based on a condition
     * @param positionId The ID of the position to partition
     * @param variable The variable (event ID) to partition on
     */
    function partitionPosition(uint256 positionId, uint256 variable) external {
        uint256 userBalance = balanceOf(msg.sender, positionId);
        if (userBalance == 0) revert NoBalanceToSplit();

        Position storage pos = positions[positionId];
        if (pos.collateralToken == IERC20(address(0))) revert PositionNotFound();

        // Split the expression into two expressions: withVar and withNotVar
        (uint256 exprWithVarId, uint256 exprWithNotVarId) =
            expressionContract.splitExpression(pos.expressionId, variable);

        // Calculate new position IDs
        uint256 positionWithVarId = getPositionId(pos.collateralToken, exprWithVarId);
        uint256 positionWithNotVarId = getPositionId(pos.collateralToken, exprWithNotVarId);

        // Burn the original position tokens
        _burn(msg.sender, positionId, userBalance);

        // Mint new position tokens
        _mint(msg.sender, positionWithVarId, userBalance, "");
        _mint(msg.sender, positionWithNotVarId, userBalance, "");

        // Update positions mapping
        if (positions[positionWithVarId].collateralToken == IERC20(address(0))) {
            positions[positionWithVarId] = Position({
                collateralToken: pos.collateralToken,
                expressionId: exprWithVarId,
                evaluatedValue: 0,
                evaluationTime: 0
            });
        }
        if (positions[positionWithNotVarId].collateralToken == IERC20(address(0))) {
            positions[positionWithNotVarId] = Position({
                collateralToken: pos.collateralToken,
                expressionId: exprWithNotVarId,
                evaluatedValue: 0,
                evaluationTime: 0
            });
        }
    }

    /**
     * @notice Splits a position by extracting a specific conjunction
     * @param positionId The ID of the position to split
     * @param conjunctionIndex The index of the conjunction to extract
     */
    function splitPositionByConjunction(uint256 positionId, uint256 conjunctionIndex) external {
        uint256 userBalance = balanceOf(msg.sender, positionId);
        if (userBalance == 0) revert NoBalanceToSplit();

        Position storage pos = positions[positionId];
        if (pos.collateralToken == IERC20(address(0))) revert PositionNotFound();

        // Split the expression into two expressions
        (uint256 singleConjExprId, uint256 remainingExprId) =
            expressionContract.splitConjunction(pos.expressionId, conjunctionIndex);

        // Calculate new position IDs
        uint256 positionSingleConjId = getPositionId(pos.collateralToken, singleConjExprId);
        uint256 positionRemainingId = getPositionId(pos.collateralToken, remainingExprId);

        // Burn the original position tokens
        _burn(msg.sender, positionId, userBalance);

        // Mint new position tokens
        _mint(msg.sender, positionSingleConjId, userBalance, "");
        _mint(msg.sender, positionRemainingId, userBalance, "");

        // Update positions mapping
        if (positions[positionSingleConjId].collateralToken == IERC20(address(0))) {
            positions[positionSingleConjId] = Position({
                collateralToken: pos.collateralToken,
                expressionId: singleConjExprId,
                evaluatedValue: 0,
                evaluationTime: 0
            });
        }
        if (positions[positionRemainingId].collateralToken == IERC20(address(0))) {
            positions[positionRemainingId] = Position({
                collateralToken: pos.collateralToken,
                expressionId: remainingExprId,
                evaluatedValue: 0,
                evaluationTime: 0
            });
        }
    }

    /**
     * @notice Merges two positions conditioned on a variable and its negation into a single position
     * @param positionWithVarId The ID of the position conditioned on Var
     * @param positionWithNotVarId The ID of the position conditioned on ¬Var
     * @param variable The variable used in the conditioning
     */
    function mergePositionsOnVariable(uint256 positionWithVarId, uint256 positionWithNotVarId, uint256 variable)
        external
    {
        uint256 userBalanceVar = balanceOf(msg.sender, positionWithVarId);
        uint256 userBalanceNotVar = balanceOf(msg.sender, positionWithNotVarId);
        if (userBalanceVar == 0 || userBalanceNotVar == 0) revert NoBalanceToMerge();

        Position storage posVar = positions[positionWithVarId];
        Position storage posNotVar = positions[positionWithNotVarId];

        // Ensure collateral tokens are the same
        if (posVar.collateralToken != posNotVar.collateralToken) revert CollateralMismatch();

        // Merge expressions conditioned on variable and its negation
        uint256 mergedExprId =
            expressionContract.mergeExpressionsOnVariable(posVar.expressionId, posNotVar.expressionId, variable);

        // Calculate new position ID
        uint256 mergedPositionId = getPositionId(posVar.collateralToken, mergedExprId);

        // Burn original position tokens
        _burn(msg.sender, positionWithVarId, userBalanceVar);
        _burn(msg.sender, positionWithNotVarId, userBalanceNotVar);

        // Mint new merged position tokens with total balance
        uint256 totalBalance = userBalanceVar + userBalanceNotVar;
        _mint(msg.sender, mergedPositionId, totalBalance, "");

        // Update positions mapping if necessary
        if (positions[mergedPositionId].collateralToken == IERC20(address(0))) {
            positions[mergedPositionId] = Position({
                collateralToken: posVar.collateralToken,
                expressionId: mergedExprId,
                evaluatedValue: 0,
                evaluationTime: 0
            });
        }
    }

    /**
     * @notice Merges two positions into one if their expressions can be merged
     * @param positionId1 The ID of the first position
     * @param positionId2 The ID of the second position
     */
    function mergePositions(uint256 positionId1, uint256 positionId2) external {
        uint256 userBalance1 = balanceOf(msg.sender, positionId1);
        uint256 userBalance2 = balanceOf(msg.sender, positionId2);
        if (userBalance1 == 0 || userBalance2 == 0) revert NoBalanceToMerge();

        Position storage pos1 = positions[positionId1];
        Position storage pos2 = positions[positionId2];

        // Ensure collateral tokens are the same
        if (pos1.collateralToken != pos2.collateralToken) revert CollateralMismatch();

        // Attempt to merge expressions
        uint256 mergedExprId = expressionContract.mergeExpressions(pos1.expressionId, pos2.expressionId);

        // Calculate new position ID
        uint256 mergedPositionId = getPositionId(pos1.collateralToken, mergedExprId);

        // Burn original position tokens
        _burn(msg.sender, positionId1, userBalance1);
        _burn(msg.sender, positionId2, userBalance2);

        // Mint new merged position tokens
        uint256 totalBalance = userBalance1 + userBalance2;
        _mint(msg.sender, mergedPositionId, totalBalance, "");

        // Update positions mapping
        if (positions[mergedPositionId].collateralToken == IERC20(address(0))) {
            positions[mergedPositionId] = Position({
                collateralToken: pos1.collateralToken,
                expressionId: mergedExprId,
                evaluatedValue: 0,
                evaluationTime: 0
            });
        }
    }

    /**
     * @notice Evaluates a position's value and caches the result
     */
    function evaluatePosition(uint256 positionId) public returns (uint256 value, bool isComplete) {
        Position storage pos = positions[positionId];
        if (pos.collateralToken == IERC20(address(0))) revert PositionNotFound();

        // Get variable IDs from the expression
        uint256[] memory variables = expressionContract.getExpressionVariables(pos.expressionId);
        uint256[] memory variableValues = new uint256[](variables.length);

        // Check if all events are settled
        for (uint256 i = 0; i < variables.length; i++) {
            (bool settled, uint256 outcome,,) = eventContract.getEventOutcome(variables[i]);
            if (!settled) {
                revert EventsNotSettled();
            }
            variableValues[i] = outcome;
        }

        // Evaluate the expression
        value = expressionContract.evaluateExpressionWithValues(pos.expressionId, variables, variableValues);
        pos.evaluatedValue = value;
        pos.evaluationTime = block.timestamp;
        emit PositionEvaluated(positionId, pos.expressionId, value, block.timestamp);
        return (value, true);
    }

    /**
     * @notice Partially evaluates a position based on a settled variable
     * @param positionId The ID of the position to evaluate
     * @param variableId The settled variable ID
     * @param settledValue The settled value of the variable (between 0 and SCALE)
     */
    function partialEvaluatePosition(uint256 positionId, uint256 variableId, uint256 settledValue) external {
        uint256 userBalance = balanceOf(msg.sender, positionId);
        if (userBalance == 0) revert NoBalanceToEvaluate();

        Position storage pos = positions[positionId];
        if (pos.collateralToken == IERC20(address(0))) revert PositionNotFound();

        // Ensure settledValue is between 0 and SCALE
        if (settledValue > SCALE) revert InvalidSettledValue(settledValue);

        // Split the position into two: one assuming Var is true, one assuming Var is false
        uint256[] memory variableIds = new uint256[](1);
        variableIds[0] = variableId;

        uint256[] memory variableValuesTrue = new uint256[](1);
        variableValuesTrue[0] = SCALE; // Set the value for 'true'

        uint256[] memory variableValuesFalse = new uint256[](1);
        variableValuesFalse[0] = 0; // Set the value for 'false'

        // Simplify expressions assuming Var = true and Var = false
        uint256 simplifiedExprIdTrue =
            expressionContract.simplifyExpression(pos.expressionId, variableIds, variableValuesTrue);
        uint256 simplifiedExprIdFalse =
            expressionContract.simplifyExpression(pos.expressionId, variableIds, variableValuesFalse);

        // Calculate new position IDs
        uint256 positionTrueId = getPositionId(pos.collateralToken, simplifiedExprIdTrue);
        uint256 positionFalseId = getPositionId(pos.collateralToken, simplifiedExprIdFalse);

        // Calculate adjusted token amounts based on settledValue
        uint256 amountTrue = (userBalance * settledValue) / SCALE;
        uint256 amountFalse = userBalance - amountTrue; // Remaining balance

        // Burn the original position tokens
        _burn(msg.sender, positionId, userBalance);

        // Mint new position tokens with adjusted amounts
        if (amountTrue > 0) {
            _mint(msg.sender, positionTrueId, amountTrue, "");
            // Update positions mapping if necessary
            if (positions[positionTrueId].collateralToken == IERC20(address(0))) {
                positions[positionTrueId] = Position({
                    collateralToken: pos.collateralToken,
                    expressionId: simplifiedExprIdTrue,
                    evaluatedValue: 0,
                    evaluationTime: 0
                });
            }
        }
        if (amountFalse > 0) {
            _mint(msg.sender, positionFalseId, amountFalse, "");
            // Update positions mapping if necessary
            if (positions[positionFalseId].collateralToken == IERC20(address(0))) {
                positions[positionFalseId] = Position({
                    collateralToken: pos.collateralToken,
                    expressionId: simplifiedExprIdFalse,
                    evaluatedValue: 0,
                    evaluationTime: 0
                });
            }
        }

        // Emit events if necessary
        emit PositionPartiallyEvaluated(positionId, variableId, settledValue, block.timestamp);
    }

    /**
     * @notice Redeems a position for collateral using continuous payout
     */
    function redeemPosition(uint256 positionId, uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        uint256 balance = balanceOf(msg.sender, positionId);
        if (balance < amount) revert NoBalanceToRedeem();

        Position storage pos = positions[positionId];
        if (pos.collateralToken == IERC20(address(0))) revert PositionNotFound();

        uint256 value;

        // Get evaluation result
        if (pos.evaluationTime == 0) {
            // Not evaluated yet
            bool isComplete;
            (value, isComplete) = evaluatePosition(positionId);

            if (!isComplete) revert EventsNotSettled();
        } else {
            value = pos.evaluatedValue;
        }

        // Calculate payout based on continuous value
        uint256 payout = (amount * value) / SCALE;

        // Update state
        _burn(msg.sender, positionId, amount);

        // Transfer collateral
        pos.collateralToken.safeTransfer(msg.sender, payout);

        emit PositionRedeemed(positionId, pos.expressionId, address(pos.collateralToken), amount, payout);
    }

    /**
     * @notice Gets cached position evaluation if available
     */
    function getPositionValue(uint256 positionId)
        external
        view
        returns (uint256 value, uint256 timestamp, bool isEvaluated)
    {
        Position storage pos = positions[positionId];
        return (pos.evaluatedValue, pos.evaluationTime, pos.evaluationTime != 0);
    }
}
