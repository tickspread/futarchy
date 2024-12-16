// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/FaoInterfaces.sol";
import "../pools/DualAuctionManager.sol";
import "./ProposalManager.sol";
import "../pools/PoolManager.sol";
import "../oracle/FaoOracleSafe.sol";
import "./FaoToken.sol";

contract FaoGovernor is Ownable, ReentrancyGuard {
    // Core contracts
    FAOToken public immutable faoToken;
    DualAuctionManager public immutable auctionManager;
    ProposalManager public immutable proposalManager;
    PoolManager public immutable poolManager;
    FaoOracleSafe public immutable oracle;

    // Protocol addresses
    address public immutable treasury;
    address public multisig;

    // Events for contract setup and admin changes
    event ContractsDeployed(
        address indexed faoToken,
        address indexed auctionManager,
        address indexed proposalManager,
        address poolManager,
        address oracle
    );
    event MultisigUpdated(address indexed oldMultisig, address indexed newMultisig);

    // Detailed proposal execution events
    event ProposalExecutionStarted(bytes32 indexed proposalHash, uint256 actionsCount);
    event ProposalActionExecuted(
        bytes32 indexed proposalHash,
        uint256 indexed actionIndex,
        address target,
        uint256 value,
        bytes data,
        bool success
    );
    event ProposalExecutionCompleted(
        bytes32 indexed proposalHash, bool allActionsSucceeded, uint256 successCount, uint256 failureCount
    );

    modifier onlyMultisig() {
        require(msg.sender == multisig, "Not multisig");
        _;
    }

    constructor(
        address _faoToken,
        address _treasury,
        address _multisig,
        address _balancerVault,
        address _proposalNFT,
        address _weth
    ) Ownable(msg.sender) {
        require(_faoToken != address(0), "Zero address");
        require(_treasury != address(0), "Zero address");
        require(_multisig != address(0), "Zero address");
        require(_balancerVault != address(0), "Zero address");
        require(_proposalNFT != address(0), "Zero address");
        require(_weth != address(0), "Zero address");

        treasury = _treasury;
        multisig = _multisig;

        // Deploy core contracts
        faoToken = FAOToken(_faoToken);
        auctionManager = new DualAuctionManager(address(faoToken), _proposalNFT, address(this));
        poolManager = new PoolManager(address(this), address(faoToken), _weth, _balancerVault);
        oracle = new FaoOracleSafe(address(poolManager));
        proposalManager = new ProposalManager(
            address(auctionManager),
            address(poolManager),
            address(oracle),
            _multisig,
            address(this) // Pass governor address
        );

        // Set up permissions
        faoToken.setProposer(address(proposalManager));

        emit ContractsDeployed(
            address(faoToken), address(auctionManager), address(proposalManager), address(poolManager), address(oracle)
        );
    }

    // Execute proposal actions, continue on failures
    function executeProposal(address[] calldata targets, uint256[] calldata values, bytes[] calldata calldatas)
        external
        returns (bool)
    {
        require(msg.sender == address(proposalManager), "Not proposal manager");

        bytes32 proposalHash = keccak256(abi.encode(targets, values, calldatas));
        emit ProposalExecutionStarted(proposalHash, targets.length);

        uint256 successCount = 0;
        uint256 failureCount = 0;

        for (uint256 i = 0; i < targets.length; i++) {
            // Execute action and capture result
            (bool success,) = targets[i].call{ value: values[i] }(calldatas[i]);

            // Record result but continue regardless of success/failure
            if (success) {
                successCount++;
            } else {
                failureCount++;
            }

            emit ProposalActionExecuted(proposalHash, i, targets[i], values[i], calldatas[i], success);
        }

        bool allSucceeded = failureCount == 0;
        emit ProposalExecutionCompleted(proposalHash, allSucceeded, successCount, failureCount);

        // Return success status but proposal is considered "executed" either way
        return allSucceeded;
    }

    function updateMultisig(address newMultisig) external onlyMultisig {
        require(newMultisig != address(0), "Zero address");
        emit MultisigUpdated(multisig, newMultisig);
        multisig = newMultisig;
    }

    // View functions with corrected return values
    function getActiveProposal()
        external
        view
        returns (address proposer, uint256 nftId, bool isEmergency, uint256 submitTime, bool isCritical, bool executed)
    {
        return proposalManager.getActiveProposal();
    }

    function getCurrentAuctionPrice() external view returns (uint256) {
        return auctionManager.getCurrentPrice();
    }

    // Allow receiving ETH
    receive() external payable { }
}
