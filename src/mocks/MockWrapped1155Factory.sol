// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IWrapped1155Factory.sol";

contract MockWrapped1155Factory is IWrapped1155Factory {
    mapping(bytes32 => address) public wrappedTokens;

    function requireWrapped1155(IERC20 token, uint256 tokenId, bytes calldata /*data*/ ) external returns (address) {
        bytes32 key = keccak256(abi.encodePacked(token, tokenId));
        if (wrappedTokens[key] == address(0)) {
            // Create deterministic address based on inputs
            wrappedTokens[key] = address(uint160(uint256(key)));
        }
        return wrappedTokens[key];
    }

    function getWrapped1155(IERC20 token, uint256 tokenId, bytes calldata /*data*/ ) external pure returns (address) {
        bytes32 key = keccak256(abi.encodePacked(token, tokenId));
        // Return same deterministic address as requireWrapped1155
        return address(uint160(uint256(key)));
    }

    function unwrap(IERC20 _token, uint256 _tokenId, uint256 _amount, address _recipient, bytes calldata _data)
        external
    {
        // Mock implementation - no actual unwrapping needed for tests
    }
}
