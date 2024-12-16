// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ExpressionEvaluatorLib
 * @notice Evaluates logical expressions with gas safety features
 */
library ExpressionEvaluatorLib {
    uint256 private constant SCALE = 1e18;
    uint256 private constant MAX_LITERALS = 128;
    uint256 private constant MAX_CONJUNCTIONS = 1024;

    // Conservative round numbers for gas estimation
    uint256 private constant GAS_PER_LITERAL = 5000;
    uint256 private constant GAS_BASE_PER_CONJUNCTION = 10000;
    uint256 private constant GAS_OVERHEAD = 20000;

    error ValueAboveScale(uint256 value);
    error RangeError(uint256 start, uint256 end, uint256 total);
    error ConjunctionTooLarge(uint256 size);
    error VariableValueNotProvided(uint256 varId);
    error LengthMismatch();

    /**
     * @notice Get complexity metrics for an expression
     */
    function getExpressionComplexity(uint256[][] memory conjunctions)
        internal
        pure
        returns (uint256 totalConjunctions, uint256 maxLiterals, uint256 totalLiterals, uint256 estimatedGas)
    {
        totalConjunctions = conjunctions.length;
        if (totalConjunctions > MAX_CONJUNCTIONS) revert ConjunctionTooLarge(totalConjunctions);

        for (uint256 i = 0; i < conjunctions.length; i++) {
            uint256 numLiterals = conjunctions[i].length;
            if (numLiterals > MAX_LITERALS) revert ConjunctionTooLarge(numLiterals);

            totalLiterals += numLiterals;
            if (numLiterals > maxLiterals) {
                maxLiterals = numLiterals;
            }
        }

        estimatedGas = GAS_OVERHEAD + (totalConjunctions * GAS_BASE_PER_CONJUNCTION) + (totalLiterals * GAS_PER_LITERAL);
    }

    /**
     * @notice Evaluate a single conjunction using arrays of variable IDs and values
     */
    function evaluateConjunctionWithValues(
        uint256[] memory literals,
        uint256[] memory variableIds,
        uint256[] memory variableValues
    ) internal pure returns (uint256) {
        if (literals.length > MAX_LITERALS) revert ConjunctionTooLarge(literals.length);
        if (variableIds.length != variableValues.length) revert LengthMismatch();

        uint256 result = SCALE;

        for (uint256 i = 0; i < literals.length; i++) {
            uint256 literal = literals[i];
            uint256 varId = literal & ((1 << 255) - 1);
            bool isNegated = (literal & (1 << 255)) != 0;

            // Find the value of varId in variableIds and variableValues
            uint256 value = 0;
            bool found = false;
            for (uint256 j = 0; j < variableIds.length; j++) {
                if (variableIds[j] == varId) {
                    value = variableValues[j];
                    found = true;
                    break;
                }
            }
            if (!found) {
                // Variable value not found
                revert VariableValueNotProvided(varId);
            }

            if (value > SCALE) revert ValueAboveScale(value);

            if (isNegated) {
                value = SCALE - value;
            }

            result = (result * value) / SCALE;
            if (result == 0) break;
        }

        return result;
    }

    /**
     * @notice Evaluate an expression using arrays of variable IDs and values
     */
    function evaluateExpressionWithValues(
        uint256[][] memory conjunctions,
        uint256[] memory variableIds,
        uint256[] memory variableValues
    ) internal pure returns (uint256) {
        if (conjunctions.length > MAX_CONJUNCTIONS) revert ConjunctionTooLarge(conjunctions.length);

        uint256 total = 0;

        for (uint256 i = 0; i < conjunctions.length; i++) {
            uint256 conjunctionValue = evaluateConjunctionWithValues(conjunctions[i], variableIds, variableValues);
            total += conjunctionValue;
            if (total >= SCALE) {
                return SCALE;
            }
        }
        return total;
    }
}
