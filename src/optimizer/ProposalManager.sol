// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/FaoInterfaces.sol";

contract ProposalManager is Ownable, ReentrancyGuard {
    // Core contracts and addresses
    IProposalNFT public immutable proposalNFT;
    IPoolManager public immutable poolManager;
    IOracle public immutable oracle;
    IFAOGovernor public immutable governor;
    address public immutable multisig;

    // Proposal parameters
    uint256 public constant PROPOSAL_SUBMIT_WINDOW = 3 days;
    uint256 public constant MIN_PROPOSAL_DURATION = 7 days;
    uint256 public constant MAX_PROPOSAL_DURATION = 28 days;
    uint256 public constant CRITICAL_FLAG_WINDOW = 3 days;

    // NFT tracking
    uint256 public nextRegularId = 1; // Start with NFT #1
    uint256 public activeEmergencyId; // If not 0, an emergency NFT exists and must be used first

    struct Proposal {
        address proposer;
        uint256 nftId;
        bool isEmergency;
        uint256 submitTime;
        bool isCritical;
        bool executed;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
    }

    Proposal public currentProposal;

    event ProposalSubmitted(address indexed proposer, uint256 indexed nftId, bool isEmergency, bytes32 proposalHash);
    event ProposalMarkedCritical(bytes32 indexed proposalHash);
    event ProposalExecuted(bytes32 indexed proposalHash);
    event EmergencyNFTActivated(uint256 indexed emergencyId);

    constructor(address _proposalNFT, address _poolManager, address _oracle, address _multisig, address _governor)
        Ownable(msg.sender)
    {
        require(_proposalNFT != address(0), "Zero address");
        require(_poolManager != address(0), "Zero address");
        require(_oracle != address(0), "Zero address");
        require(_multisig != address(0), "Zero address");
        require(_governor != address(0), "Zero address");

        proposalNFT = IProposalNFT(_proposalNFT);
        poolManager = IPoolManager(_poolManager);
        oracle = IOracle(_oracle);
        multisig = _multisig;
        governor = IFAOGovernor(_governor);
    }

    function submitProposal(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        uint256 nftId,
        bool isEmergency
    ) external nonReentrant {
        require(targets.length > 0, "Empty proposal");
        require(targets.length == values.length && values.length == calldatas.length, "Length mismatch");

        // Verify NFT ownership and usage
        require(proposalNFT.ownerOf(nftId) == msg.sender, "Not NFT owner");
        require(!proposalNFT.isUsed(nftId, isEmergency), "NFT already used");

        // Check sequencing
        if (isEmergency) {
            require(nftId == activeEmergencyId, "Wrong emergency NFT");
            activeEmergencyId = 0; // Clear emergency slot
        } else {
            require(activeEmergencyId == 0, "Must use emergency NFT first");
            require(nftId == nextRegularId, "Wrong NFT sequence");
            nextRegularId++;
        }

        // Mark NFT as used
        proposalNFT.markUsed(nftId, isEmergency);

        // Store proposal
        currentProposal = Proposal({
            proposer: msg.sender,
            nftId: nftId,
            isEmergency: isEmergency,
            submitTime: block.timestamp,
            isCritical: false,
            executed: false,
            targets: targets,
            values: values,
            calldatas: calldatas
        });

        bytes32 proposalHash = keccak256(abi.encode(targets, values, calldatas));
        emit ProposalSubmitted(msg.sender, nftId, isEmergency, proposalHash);
    }

    function activateEmergencyNFT(uint256 emergencyId) external {
        require(msg.sender == address(proposalNFT), "Not NFT contract");
        activeEmergencyId = emergencyId;
        emit EmergencyNFTActivated(emergencyId);
    }

    function markCritical() external {
        require(msg.sender == multisig, "Not multisig");
        require(!currentProposal.executed, "Already executed");
        require(block.timestamp <= currentProposal.submitTime + CRITICAL_FLAG_WINDOW, "Flag window expired");
        require(!currentProposal.isCritical, "Already critical");

        currentProposal.isCritical = true;

        bytes32 proposalHash =
            keccak256(abi.encode(currentProposal.targets, currentProposal.values, currentProposal.calldatas));
        emit ProposalMarkedCritical(proposalHash);
    }

    function executeProposal() external nonReentrant {
        Proposal storage proposal = currentProposal;
        require(!proposal.executed, "Already executed");

        // Check submission window
        require(block.timestamp <= proposal.submitTime + PROPOSAL_SUBMIT_WINDOW, "Submit window expired");

        // Check TWAP period
        uint256 requiredWait = proposal.isCritical ? MAX_PROPOSAL_DURATION : MIN_PROPOSAL_DURATION;
        require(block.timestamp >= proposal.submitTime + requiredWait, "TWAP period not elapsed");

        // Check oracle outcome
        require(IOracle(oracle).checkProposalOutcome(proposal.isCritical), "Proposal rejected");

        // Execute through governor
        bool success = governor.executeProposal(proposal.targets, proposal.values, proposal.calldatas);

        // Mark as executed regardless of success
        proposal.executed = true;

        bytes32 proposalHash = keccak256(abi.encode(proposal.targets, proposal.values, proposal.calldatas));
        emit ProposalExecuted(proposalHash);

        // If proposal was successful, merge pools
        if (success) {
            poolManager.mergePools();
        }
    }

    function getActiveProposal()
        external
        view
        returns (address proposer, uint256 nftId, bool isEmergency, uint256 submitTime, bool isCritical, bool executed)
    {
        return (
            currentProposal.proposer,
            currentProposal.nftId,
            currentProposal.isEmergency,
            currentProposal.submitTime,
            currentProposal.isCritical,
            currentProposal.executed
        );
    }
}
