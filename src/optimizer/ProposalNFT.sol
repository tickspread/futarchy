// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ProposalNFT is ERC721, Ownable {
    // Mapping from token ID to usage status
    mapping(uint256 => bool) public regularUsed;
    mapping(uint256 => bool) public emergencyUsed;

    // Counter for token IDs
    uint256 private _nextTokenId = 1;

    constructor() ERC721("Futarchy Proposal NFT", "FPNFT") Ownable() { }

    function mint(address to, uint256 proposalId) external onlyOwner {
        require(proposalId == _nextTokenId, "Invalid proposal ID");
        _safeMint(to, proposalId);
        _nextTokenId++;
    }

    function mintEmergency(address to, uint256 emergencyId) external onlyOwner {
        _safeMint(to, emergencyId);
    }

    function isUsed(uint256 tokenId, bool isEmergency) external view returns (bool) {
        if (isEmergency) {
            return emergencyUsed[tokenId];
        }
        return regularUsed[tokenId];
    }

    function markUsed(uint256 tokenId, bool isEmergency) external onlyOwner {
        if (isEmergency) {
            require(!emergencyUsed[tokenId], "Emergency NFT already used");
            emergencyUsed[tokenId] = true;
        } else {
            require(!regularUsed[tokenId], "Regular NFT already used");
            regularUsed[tokenId] = true;
        }
    }

    function getNextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }
}
