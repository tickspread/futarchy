// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CanonicalFormLib.sol";
import "./ExpressionEvaluatorLib.sol";

/**
 * @title ExpressionContract
 * @notice Manages logical expressions in DNF form with evaluation capabilities
 */
contract ExpressionContract {
    using CanonicalFormLib for uint256[][];
    using ExpressionEvaluatorLib for uint256[][];

    uint256 private constant MAX_LITERALS = 256;
    uint256 private constant MAX_CONJUNCTIONS = 1024;

    error ExpressionDoesNotExist(uint256 expressionId);
    error InvalidLiteral();
    error ExpressionTooLarge();
    error InvalidBooleanValue(uint256 value);
    error LengthMismatch();
    error ExpressionsCannotBeMerged();

    uint256 public constant SCALE = 1e18;

    struct Expression {
        uint256 expressionId;
        uint256[][] conjunctions;
    }

    uint256 private nextExpressionId = 1;
    mapping(uint256 => Expression) public expressions;
    mapping(bytes32 => uint256) private expressionHashes;

    event ExpressionCreated(uint256 indexed expressionId, bytes32 indexed hash);

    constructor() {
        // Create TRUE expression (expressionId = 1)
        uint256[][] memory trueExpr = new uint256[][](1);
        trueExpr[0] = new uint256[](0);
        _createExpression(trueExpr);

        // Create FALSE expression (expressionId = 2)
        uint256[][] memory falseExpr = new uint256[][](0);
        _createExpression(falseExpr);
    }

    /**
     * @notice Creates a literal expression
     */
    function createLiteralExpression(int256 literal) public returns (uint256) {
        if (literal == 0) revert InvalidLiteral();

        uint256[][] memory conj = new uint256[][](1);
        conj[0] = new uint256[](1);
        conj[0][0] = literal > 0 ? uint256(literal) : (uint256(-literal) | (1 << 255));

        return _createExpression(conj);
    }

    /**
     * @notice Get the TRUE expression ID
     */
    function getTrueExpressionId() public pure returns (uint256) {
        return 1;
    }

    /**
     * @notice Get the FALSE expression ID
     */
    function getFalseExpressionId() public pure returns (uint256) {
        return 2;
    }

    function expressionExists(uint256 expressionId) external view returns (bool) {
        return expressions[expressionId].expressionId != 0;
    }

    /**
     * @notice Combines expressions with OR
     */
    function orExpressions(uint256 exprId1, uint256 exprId2) public returns (uint256) {
        Expression storage expr1 = _getExpression(exprId1);
        Expression storage expr2 = _getExpression(exprId2);

        if (expr1.conjunctions.length + expr2.conjunctions.length > MAX_CONJUNCTIONS) {
            revert ExpressionTooLarge();
        }

        uint256[][] memory combined = new uint256[][](expr1.conjunctions.length + expr2.conjunctions.length);

        for (uint256 i = 0; i < expr1.conjunctions.length; i++) {
            combined[i] = expr1.conjunctions[i];
        }
        for (uint256 i = 0; i < expr2.conjunctions.length; i++) {
            combined[expr1.conjunctions.length + i] = expr2.conjunctions[i];
        }

        return _createExpression(combined);
    }

    /**
     * @notice Combines expressions with AND
     */
    function andExpressions(uint256 exprId1, uint256 exprId2) public returns (uint256) {
        Expression storage expr1 = _getExpression(exprId1);
        Expression storage expr2 = _getExpression(exprId2);

        if (expr1.conjunctions.length * expr2.conjunctions.length > MAX_CONJUNCTIONS) {
            revert ExpressionTooLarge();
        }

        uint256[][] memory combined = new uint256[][](expr1.conjunctions.length * expr2.conjunctions.length);
        uint256 index = 0;

        for (uint256 i = 0; i < expr1.conjunctions.length; i++) {
            for (uint256 j = 0; j < expr2.conjunctions.length; j++) {
                uint256 newSize = expr1.conjunctions[i].length + expr2.conjunctions[j].length;
                if (newSize > MAX_LITERALS) revert ExpressionTooLarge();

                uint256[] memory literals = new uint256[](newSize);
                for (uint256 k = 0; k < expr1.conjunctions[i].length; k++) {
                    literals[k] = expr1.conjunctions[i][k];
                }
                for (uint256 k = 0; k < expr2.conjunctions[j].length; k++) {
                    literals[expr1.conjunctions[i].length + k] = expr2.conjunctions[j][k];
                }

                combined[index++] = literals;
            }
        }

        return _createExpression(combined);
    }

    /**
     * @notice Splits an expression into two based on a variable
     * @param expressionId Expression to split
     * @param variable Variable to split on
     * @return withVar Expression AND variable
     * @return withNotVar Expression AND NOT variable
     */
    function splitExpression(uint256 expressionId, uint256 variable)
        public
        returns (uint256 withVar, uint256 withNotVar)
    {
        Expression storage expr = _getExpression(expressionId);
        uint256 numConjunctions = expr.conjunctions.length;

        // Check if the number of conjunctions exceeds MAX_CONJUNCTIONS
        if (numConjunctions > MAX_CONJUNCTIONS) {
            revert ExpressionTooLarge();
        }

        // Initialize arrays for new expressions
        uint256[][] memory conjWithVar = new uint256[][](numConjunctions);
        uint256[][] memory conjWithNotVar = new uint256[][](numConjunctions);

        for (uint256 i = 0; i < numConjunctions; i++) {
            uint256 origConjLength = expr.conjunctions[i].length;

            // Check if adding the variable would exceed MAX_LITERALS
            if (origConjLength + 1 > MAX_LITERALS) {
                revert ExpressionTooLarge();
            }

            // Create new conjunctions with added variable
            uint256[] memory newConjWithVar = new uint256[](origConjLength + 1);
            uint256[] memory newConjWithNotVar = new uint256[](origConjLength + 1);

            // Copy original literals
            for (uint256 j = 0; j < origConjLength; j++) {
                newConjWithVar[j] = expr.conjunctions[i][j];
                newConjWithNotVar[j] = expr.conjunctions[i][j];
            }

            // Add variable and its negation
            newConjWithVar[origConjLength] = variable;
            newConjWithNotVar[origConjLength] = variable | (1 << 255);

            conjWithVar[i] = newConjWithVar;
            conjWithNotVar[i] = newConjWithNotVar;
        }

        // Create new expressions, ensuring they don't exceed MAX_CONJUNCTIONS
        withVar = _createExpression(conjWithVar);
        withNotVar = _createExpression(conjWithNotVar);
    }

    function splitConjunction(uint256 expressionId, uint256 conjunctionIndex)
        public
        returns (uint256 singleConjExprId, uint256 remainingExprId)
    {
        Expression storage expr = _getExpression(expressionId);

        if (conjunctionIndex >= expr.conjunctions.length) {
            revert ExpressionDoesNotExist(conjunctionIndex);
        }

        // Create the expression with the single conjunction
        uint256[][] memory singleConj = new uint256[][](1);
        singleConj[0] = expr.conjunctions[conjunctionIndex];
        singleConjExprId = _createExpression(singleConj);

        // Create the expression with the remaining conjunctions
        uint256 remainingConjLength = expr.conjunctions.length - 1;

        // Ensure we don't exceed MAX_CONJUNCTIONS
        if (remainingConjLength > MAX_CONJUNCTIONS) {
            revert ExpressionTooLarge();
        }

        uint256[][] memory remainingConj = new uint256[][](remainingConjLength);
        uint256 index = 0;
        for (uint256 i = 0; i < expr.conjunctions.length; i++) {
            if (i != conjunctionIndex) {
                remainingConj[index++] = expr.conjunctions[i];
            }
        }
        remainingExprId = _createExpression(remainingConj);
    }

    function mergeExpressionsOnVariable(uint256 exprWithVarId, uint256 exprWithNotVarId, uint256 variable)
        public
        returns (uint256 mergedExprId)
    {
        Expression storage exprWithVar = _getExpression(exprWithVarId);
        Expression storage exprWithNotVar = _getExpression(exprWithNotVarId);

        // Strip the variable from both expressions
        uint256[][] memory strippedConj1 = stripVariableFromConjunctions(exprWithVar.conjunctions, variable, false);
        uint256[][] memory strippedConj2 = stripVariableFromConjunctions(exprWithNotVar.conjunctions, variable, true);

        // Compute hashes to compare the stripped expressions
        bytes32 hash1 = strippedConj1.computeExpressionHash();
        bytes32 hash2 = strippedConj2.computeExpressionHash();

        if (hash1 != hash2) {
            revert ExpressionsCannotBeMerged();
        }

        // Create the merged expression (E)
        mergedExprId = _createExpression(strippedConj1);
    }

    function stripVariableFromConjunctions(uint256[][] memory conjunctions, uint256 variable, bool isNegated)
        private
        pure
        returns (uint256[][] memory strippedConjunctions)
    {
        strippedConjunctions = new uint256[][](conjunctions.length);

        for (uint256 i = 0; i < conjunctions.length; i++) {
            uint256[] memory conj = conjunctions[i];
            uint256[] memory tempConj = new uint256[](conj.length);
            uint256 index = 0;
            bool foundVar = false;

            for (uint256 j = 0; j < conj.length; j++) {
                uint256 lit = conj[j];
                uint256 varId = lit & ((1 << 255) - 1);
                bool litIsNegated = (lit & (1 << 255)) != 0;

                if (varId == variable && litIsNegated == isNegated) {
                    foundVar = true;
                    // Skip this literal
                } else {
                    tempConj[index++] = lit;
                }
            }

            if (!foundVar) {
                // Variable not found in conjunction; cannot merge
                revert ExpressionsCannotBeMerged();
            }

            // Resize the array to the actual number of literals
            uint256[] memory newConj = new uint256[](index);
            for (uint256 k = 0; k < index; k++) {
                newConj[k] = tempConj[k];
            }

            strippedConjunctions[i] = newConj;
        }
    }

    function mergeExpressions(uint256 exprId1, uint256 exprId2) public returns (uint256 mergedExprId) {
        Expression storage expr1 = _getExpression(exprId1);
        Expression storage expr2 = _getExpression(exprId2);

        uint256 totalConjunctions = expr1.conjunctions.length + expr2.conjunctions.length;

        // Ensure the total number of conjunctions does not exceed MAX_CONJUNCTIONS
        if (totalConjunctions > MAX_CONJUNCTIONS) {
            revert ExpressionTooLarge();
        }

        uint256[][] memory mergedConjunctions = new uint256[][](totalConjunctions);

        // Copy conjunctions from expr1
        for (uint256 i = 0; i < expr1.conjunctions.length; i++) {
            mergedConjunctions[i] = expr1.conjunctions[i];
        }

        // Copy conjunctions from expr2
        for (uint256 i = 0; i < expr2.conjunctions.length; i++) {
            mergedConjunctions[expr1.conjunctions.length + i] = expr2.conjunctions[i];
        }

        mergedExprId = _createExpression(mergedConjunctions);
    }

    /**
     * @notice Computes intersection of two expressions
     * @param expr1Id First expression
     * @param expr2Id Second expression
     * @return intersectionId Intersection of expressions
     */
    function intersectExpressions(uint256 expr1Id, uint256 expr2Id) public returns (uint256 intersectionId) {
        Expression storage expr1 = _getExpression(expr1Id);
        Expression storage expr2 = _getExpression(expr2Id);

        uint256[][] memory intersectionConj = new uint256[][](expr1.conjunctions.length * expr2.conjunctions.length);
        uint256 intersectionCount = 0;

        // For each pair of conjunctions, try to merge them
        for (uint256 i = 0; i < expr1.conjunctions.length; i++) {
            for (uint256 j = 0; j < expr2.conjunctions.length; j++) {
                (uint256[] memory mergedConj, bool isValid) =
                    mergeConjunctions(expr1.conjunctions[i], expr2.conjunctions[j]);
                if (isValid) {
                    intersectionConj[intersectionCount++] = mergedConj;
                }
            }
        }

        // Create intersection expression
        uint256[][] memory finalIntersection = new uint256[][](intersectionCount);
        for (uint256 i = 0; i < intersectionCount; i++) {
            finalIntersection[i] = intersectionConj[i];
        }
        intersectionId = _createExpression(finalIntersection);
    }

    /**
     * @notice Helper to merge two conjunctions, detecting contradictions
     * @return merged The merged conjunction
     * @return isValid False if conjunctions have contradicting literals
     */
    function mergeConjunctions(uint256[] memory conj1, uint256[] memory conj2)
        private
        pure
        returns (uint256[] memory merged, bool isValid)
    {
        uint256[] memory temp = new uint256[](conj1.length + conj2.length);
        uint256 count = 0;

        // Copy first conjunction
        for (uint256 i = 0; i < conj1.length; i++) {
            temp[count++] = conj1[i];
        }

        // Add literals from second conjunction, checking for contradictions
        for (uint256 i = 0; i < conj2.length; i++) {
            uint256 lit2 = conj2[i];
            uint256 var2 = lit2 & ((1 << 255) - 1);
            bool isNegated2 = (lit2 & (1 << 255)) != 0;

            // Check against all existing literals
            bool isDuplicate = false;
            for (uint256 j = 0; j < count; j++) {
                uint256 lit1 = temp[j];
                uint256 var1 = lit1 & ((1 << 255) - 1);
                bool isNegated1 = (lit1 & (1 << 255)) != 0;

                if (var1 == var2) {
                    if (isNegated1 != isNegated2) {
                        // Contradiction found
                        return (new uint256[](0), false);
                    }
                    isDuplicate = true;
                    break;
                }
            }

            if (!isDuplicate) {
                temp[count++] = lit2;
            }
        }

        // Create final array of exact size
        merged = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            merged[i] = temp[i];
        }
        return (merged, true);
    }

    /**
     * @notice Simplifies an expression based on settled variables
     * @param expressionId The ID of the expression to simplify
     * @param variableIds Array of variable IDs that have been settled
     * @param variableValues Array of corresponding settled values
     * @return simplifiedExprId The ID of the simplified expression
     */
    function simplifyExpression(uint256 expressionId, uint256[] memory variableIds, uint256[] memory variableValues)
        public
        returns (uint256 simplifiedExprId)
    {
        if (variableIds.length != variableValues.length) revert LengthMismatch();

        // Ensure all variable values are 0 or SCALE
        // Cannot simplify expressions with values settled to intermediate values
        for (uint256 i = 0; i < variableValues.length; i++) {
            uint256 val = variableValues[i];
            if (val != 0 && val != SCALE) revert InvalidBooleanValue(val);
        }

        Expression storage expr = _getExpression(expressionId);
        uint256 conjCount = expr.conjunctions.length;

        // Prepare a new set of conjunctions after simplification
        uint256[][] memory newConjunctions = new uint256[][](conjCount);
        uint256 newConjCount = 0;

        for (uint256 i = 0; i < conjCount; i++) {
            (bool removeConj, uint256[] memory finalConj) =
                _simplifyConjunction(expr.conjunctions[i], variableIds, variableValues);
            if (!removeConj) {
                newConjunctions[newConjCount++] = finalConj;
            }
        }

        // Resize final array
        uint256[][] memory finalConjunctions = new uint256[][](newConjCount);
        for (uint256 m = 0; m < newConjCount; m++) {
            finalConjunctions[m] = newConjunctions[m];
        }

        simplifiedExprId = _createExpression(finalConjunctions);
    }

    function _simplifyConjunction(uint256[] memory conj, uint256[] memory variableIds, uint256[] memory variableValues)
        internal
        pure
        returns (bool removeConj, uint256[] memory finalConj)
    {
        uint256[] memory tempLiterals = new uint256[](conj.length);
        uint256 litCount = 0;

        for (uint256 j = 0; j < conj.length; j++) {
            uint256 literal = conj[j];
            (bool isSettled, uint256 settledVal) = _getSettledValue(literal, variableIds, variableValues);

            if (isSettled) {
                // If settledVal == 0, this literal is false => entire conjunction is removed
                if (settledVal == 0) {
                    return (true, new uint256[](0));
                }
                // Else settledVal == SCALE (this function cannot be called with intermediate values)
                // So literal is true => omit this literal and continue
            } else {
                // Variable not settled, keep this literal
                tempLiterals[litCount++] = literal;
            }
        }

        // Conjunction not removed
        finalConj = new uint256[](litCount);
        for (uint256 x = 0; x < litCount; x++) {
            finalConj[x] = tempLiterals[x];
        }
        removeConj = false;
    }

    function _getSettledValue(uint256 literal, uint256[] memory variableIds, uint256[] memory variableValues)
        internal
        pure
        returns (bool, uint256)
    {
        uint256 varId = literal & ((1 << 255) - 1);
        bool isNegated = (literal & (1 << 255)) != 0;

        for (uint256 k = 0; k < variableIds.length; k++) {
            if (variableIds[k] == varId) {
                uint256 settledVal = variableValues[k];
                if (isNegated) {
                    settledVal = SCALE - settledVal;
                }
                return (true, settledVal);
            }
        }

        return (false, 0);
    }

    function expressionsHaveIntersection(uint256 exprId1, uint256 exprId2) public view returns (bool hasIntersection) {
        Expression storage expr1 = _getExpression(exprId1);
        Expression storage expr2 = _getExpression(exprId2);

        // For each pair of conjunctions, check if they can be merged
        for (uint256 i = 0; i < expr1.conjunctions.length; i++) {
            for (uint256 j = 0; j < expr2.conjunctions.length; j++) {
                (, bool isValid) = mergeConjunctions(expr1.conjunctions[i], expr2.conjunctions[j]);
                if (isValid) {
                    return true; // Intersection exists
                }
            }
        }
        return false; // No intersection
    }

    /**
     * @notice Get complexity metrics for an expression
     */
    function getExpressionComplexity(uint256 expressionId)
        public
        view
        returns (uint256 totalConjunctions, uint256 maxLiterals, uint256 totalLiterals, uint256 estimatedGas)
    {
        Expression storage expr = _getExpression(expressionId);
        return expr.conjunctions.getExpressionComplexity();
    }

    /**
     * @notice Gets all unique variables used in an expression
     * @param expressionId The expression to analyze
     * @return variables Array of variable IDs (without negation flags)
     */
    function getExpressionVariables(uint256 expressionId) public view returns (uint256[] memory variables) {
        Expression storage expr = _getExpression(expressionId);

        // Collect all variables in a temporary array
        uint256 totalLiterals;
        for (uint256 i = 0; i < expr.conjunctions.length; i++) {
            totalLiterals += expr.conjunctions[i].length;
        }

        uint256[] memory allVars = new uint256[](totalLiterals);
        uint256 idx = 0;
        for (uint256 i = 0; i < expr.conjunctions.length; i++) {
            for (uint256 j = 0; j < expr.conjunctions[i].length; j++) {
                uint256 varId = expr.conjunctions[i][j] & ((1 << 255) - 1);
                allVars[idx++] = varId;
            }
        }

        // Extract unique variables from allVars
        // A simple method: for each varId in allVars, check if we have added it before
        uint256[] memory uniqueVars = new uint256[](totalLiterals);
        uint256 uniqueCount = 0;
        for (uint256 i = 0; i < allVars.length; i++) {
            uint256 v = allVars[i];
            bool alreadyAdded = false;
            for (uint256 k = 0; k < uniqueCount; k++) {
                if (uniqueVars[k] == v) {
                    alreadyAdded = true;
                    break;
                }
            }
            if (!alreadyAdded) {
                uniqueVars[uniqueCount++] = v;
            }
        }

        variables = new uint256[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            variables[i] = uniqueVars[i];
        }
    }

    function getValueForVarId(uint256 varId, uint256[] memory variableIds, uint256[] memory variableValues)
        internal
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < variableIds.length; i++) {
            if (variableIds[i] == varId) {
                return variableValues[i];
            }
        }
        // If not found, decide on a default behavior or revert
        return 0; // or revert if needed
    }

    /**
     * @notice Evaluate a single conjunction of an expression
     */
    function evaluateConjunction(
        uint256 expressionId,
        uint256 conjunctionIndex,
        uint256[] memory variableIds,
        uint256[] memory variableValues
    ) public view returns (uint256) {
        Expression storage expr = _getExpression(expressionId);
        if (conjunctionIndex >= expr.conjunctions.length) revert ExpressionDoesNotExist(conjunctionIndex);

        uint256[] memory conj = expr.conjunctions[conjunctionIndex];

        // Evaluate the conjunction using arrays
        uint256 result = SCALE; // assuming SCALE is defined
        for (uint256 i = 0; i < conj.length; i++) {
            uint256 lit = conj[i];
            uint256 varId = lit & ((1 << 255) - 1);
            bool isNegated = (lit & (1 << 255)) != 0;

            uint256 value = getValueForVarId(varId, variableIds, variableValues);
            if (isNegated) {
                value = SCALE - value;
            }

            result = (result * value) / SCALE;
            if (result == 0) {
                break;
            }
        }

        return result;
    }

    /**
     * @notice Try to evaluate a range of conjunctions
     */
    function evaluateExpressionWithValues(
        uint256 expressionId,
        uint256[] memory variableIds,
        uint256[] memory variableValues
    ) public view returns (uint256) {
        Expression storage expr = _getExpression(expressionId);
        return ExpressionEvaluatorLib.evaluateExpressionWithValues(expr.conjunctions, variableIds, variableValues);
    }

    /**
     * @notice Internal helper to create expression in canonical form
     */
    function _createExpression(uint256[][] memory conjunctions) private returns (uint256) {
        uint256[][] memory canonical = conjunctions.canonicalizeExpression();

        bytes32 hash = canonical.computeExpressionHash();
        uint256 existingId = expressionHashes[hash];
        if (existingId != 0) {
            return existingId;
        }

        uint256 expressionId = nextExpressionId++;
        Expression storage expr = expressions[expressionId];
        expr.expressionId = expressionId;
        expr.conjunctions = canonical;
        expressionHashes[hash] = expressionId;

        emit ExpressionCreated(expressionId, hash);
        return expressionId;
    }

    /**
     * @notice Internal helper to get expression with validation
     */
    function _getExpression(uint256 expressionId) private view returns (Expression storage expr) {
        expr = expressions[expressionId];
        if (expr.expressionId == 0) revert ExpressionDoesNotExist(expressionId);
        return expr;
    }
}
