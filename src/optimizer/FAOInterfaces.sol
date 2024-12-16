// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IProposalManager {
    function getActiveProposal()
        external
        view
        returns (address proposer, uint256 nftId, bool isEmergency, uint256 submitTime, bool isCritical, bool executed);
}

interface IAuctionManager {
    function getCurrentPrice() external view returns (uint256);
}

interface IProposalNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function isUsed(uint256 tokenId, bool isEmergency) external view returns (bool);
    function markUsed(uint256 tokenId, bool isEmergency) external;
    function mint(address to, uint256 proposalId) external;
    function mintEmergency(address to, uint256 emergencyId) external;
}

interface IPoolManager {
    function mergePools() external;
    function getYesPool() external view returns (address);
    function getNoPool() external view returns (address);
    function getPoolCreationTime() external view returns (uint256);
}

interface IOracle {
    function checkProposalOutcome(bool isCritical) external view returns (bool);
}

interface IFAOGovernor {
    function executeProposal(address[] calldata targets, uint256[] calldata values, bytes[] calldata calldatas)
        external
        returns (bool);
}

interface IBalancerPool {
    function getTimeWeightedAverage(uint32[] memory queries) external view returns (uint256[] memory);
}

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
}
