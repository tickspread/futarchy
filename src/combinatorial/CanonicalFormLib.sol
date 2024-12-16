// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title CanonicalFormLib
 * @notice Library for converting expressions to canonical form and computing their hashes
 * @dev A canonical form ensures that equivalent expressions have identical representations
 */
library CanonicalFormLib {
    error DuplicateLiteral(uint256 literal);
    error ContradictoryLiterals(uint256 var1, uint256 var2);

    /**
     * @notice Sorts and deduplicates literals within a conjunction
     * @dev Also detects contradictions (x AND NOT x)
     * @param literals Array of literals to canonicalize
     * @return cleanLiterals Sorted array with no duplicates
     * @return isValid False if conjunction contains a contradiction
     */
    function canonicalizeConjunction(uint256[] memory literals)
        internal
        pure
        returns (uint256[] memory cleanLiterals, bool isValid)
    {
        if (literals.length == 0) {
            return (new uint256[](0), true);
        }

        // Sort literals first
        quickSortLiterals(literals, 0, int256(literals.length - 1));

        // Remove duplicates and check for contradictions
        uint256[] memory tempLiterals = new uint256[](literals.length);
        uint256 writeIndex = 0;

        for (uint256 readIndex = 0; readIndex < literals.length; readIndex++) {
            uint256 currentLiteral = literals[readIndex];
            uint256 currentVar = currentLiteral & ((1 << 255) - 1);
            bool currentIsNegated = (currentLiteral & (1 << 255)) != 0;

            // Skip duplicates
            if (readIndex > 0 && currentLiteral == literals[readIndex - 1]) {
                continue;
            }

            // Check for contradiction with previous literal
            if (readIndex > 0) {
                uint256 prevLiteral = literals[readIndex - 1];
                uint256 prevVar = prevLiteral & ((1 << 255) - 1);
                bool prevIsNegated = (prevLiteral & (1 << 255)) != 0;

                if (currentVar == prevVar && currentIsNegated != prevIsNegated) {
                    return (new uint256[](0), false);
                }
            }

            tempLiterals[writeIndex++] = currentLiteral;
        }

        // Create final array of exact size
        cleanLiterals = new uint256[](writeIndex);
        for (uint256 i = 0; i < writeIndex; i++) {
            cleanLiterals[i] = tempLiterals[i];
        }

        return (cleanLiterals, true);
    }

    /**
     * @notice Puts an entire expression in canonical form
     * @param conjunctions Array of conjunctions to canonicalize
     * @return canonicalForm The expression in canonical form
     */
    function canonicalizeExpression(uint256[][] memory conjunctions)
        internal
        pure
        returns (uint256[][] memory canonicalForm)
    {
        if (conjunctions.length == 0) {
            return new uint256[][](0);
        }

        // First canonicalize each conjunction
        uint256[][] memory validConjunctions = new uint256[][](conjunctions.length);
        uint256 validCount = 0;

        for (uint256 i = 0; i < conjunctions.length; i++) {
            (uint256[] memory cleanConj, bool isValid) = canonicalizeConjunction(conjunctions[i]);
            if (isValid && cleanConj.length > 0) {
                // Skip contradictory and empty conjunctions
                validConjunctions[validCount++] = cleanConj;
            }
        }

        // Sort conjunctions for canonical form
        if (validCount > 0) {
            quickSortConjunctions(validConjunctions, 0, int256(validCount - 1));
        }

        // Remove duplicate conjunctions
        canonicalForm = new uint256[][](validCount);
        uint256 writeIndex = 0;

        for (uint256 readIndex = 0; readIndex < validCount; readIndex++) {
            if (readIndex > 0 && areConjunctionsEqual(validConjunctions[readIndex], validConjunctions[readIndex - 1])) {
                continue;
            }
            canonicalForm[writeIndex++] = validConjunctions[readIndex];
        }

        // Trim array to final size
        assembly {
            mstore(canonicalForm, writeIndex)
        }

        return canonicalForm;
    }

    /**
     * @notice Compute hash of expression in canonical form
     * @param conjunctions Array of conjunctions in canonical form
     * @return Hash of the expression
     */
    function computeExpressionHash(uint256[][] memory conjunctions) internal pure returns (bytes32) {
        // Expression should already be in canonical form when this is called
        bytes memory data;

        // Serialize each conjunction
        for (uint256 i = 0; i < conjunctions.length; i++) {
            uint256[] memory conj = conjunctions[i];
            for (uint256 j = 0; j < conj.length; j++) {
                data = abi.encodePacked(data, conj[j]);
            }
            // Add separator between conjunctions
            data = abi.encodePacked(data, bytes1(0x00));
        }

        return keccak256(data);
    }

    // Sorting helper functions
    function quickSortLiterals(uint256[] memory arr, int256 left, int256 right) private pure {
        if (left >= right) return;

        uint256 pivot = arr[uint256(left + (right - left) / 2)];
        int256 i = left;
        int256 j = right;

        while (i <= j) {
            while (arr[uint256(i)] < pivot) i++;
            while (arr[uint256(j)] > pivot) j--;

            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                i++;
                j--;
            }
        }

        if (left < j) quickSortLiterals(arr, left, j);
        if (i < right) quickSortLiterals(arr, i, right);
    }

    function quickSortConjunctions(uint256[][] memory arr, int256 left, int256 right) private pure {
        if (left >= right) return;

        uint256[] memory pivot = arr[uint256(left + (right - left) / 2)];
        int256 i = left;
        int256 j = right;

        while (i <= j) {
            while (compareConjunctions(arr[uint256(i)], pivot) < 0) i++;
            while (compareConjunctions(arr[uint256(j)], pivot) > 0) j--;

            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                i++;
                j--;
            }
        }

        if (left < j) quickSortConjunctions(arr, left, j);
        if (i < right) quickSortConjunctions(arr, i, right);
    }

    function compareConjunctions(uint256[] memory conj1, uint256[] memory conj2) private pure returns (int256) {
        uint256 minLength = conj1.length < conj2.length ? conj1.length : conj2.length;

        // Compare literals
        for (uint256 i = 0; i < minLength; i++) {
            if (conj1[i] < conj2[i]) return -1;
            if (conj1[i] > conj2[i]) return 1;
        }

        // If all common literals are equal, shorter conjunction comes first
        if (conj1.length < conj2.length) return -1;
        if (conj1.length > conj2.length) return 1;
        return 0;
    }

    function areConjunctionsEqual(uint256[] memory conj1, uint256[] memory conj2) private pure returns (bool) {
        if (conj1.length != conj2.length) return false;
        for (uint256 i = 0; i < conj1.length; i++) {
            if (conj1[i] != conj2[i]) return false;
        }
        return true;
    }
}
