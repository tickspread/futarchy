// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWrapped1155Factory {
    function requireWrapped1155(IERC20 token, uint256 tokenId, bytes calldata data) external returns (address);

    function getWrapped1155(IERC20 token, uint256 tokenId, bytes calldata data) external view returns (address);

    function unwrap(IERC20 token, uint256 tokenId, uint256 amount, address recipient, bytes calldata data) external;
}
