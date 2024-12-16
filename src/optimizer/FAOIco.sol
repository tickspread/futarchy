// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./FaoTokenUpdated.sol";

contract FAOICO is ReentrancyGuard {
    FAOToken public faoToken;

    uint256 public constant TOKENS_PER_ETH = 10000;
    uint256 public constant ICO_DURATION = 28 days;
    uint256 public immutable startTime;
    uint256 public totalETHRaised;
    bool public icoComplete;

    // Track individual contributions for refunds
    mapping(address => uint256) public contributions;

    // Addresses for initial setup
    address public immutable treasury;
    address public immutable options;
    address public immutable proposer; // Will be set as owner

    event ICOInvestment(address indexed investor, uint256 ethAmount, uint256 tokenAmount);
    event ICOCompleted(uint256 totalETHRaised, uint256 totalTokens);
    event Refunded(address indexed investor, uint256 ethAmount);

    constructor(address _treasury, address _options, address _proposer) {
        require(_treasury != address(0) && _options != address(0) && _proposer != address(0), "Zero address");
        treasury = _treasury;
        options = _options;
        proposer = _proposer;
        startTime = block.timestamp;
    }

    receive() external payable {
        invest();
    }

    function invest() public payable nonReentrant {
        require(!icoComplete, "ICO is complete");
        require(block.timestamp < startTime + ICO_DURATION, "ICO period ended");
        require(msg.value > 0, "No ETH sent");

        uint256 tokenAmount = msg.value * TOKENS_PER_ETH;
        totalETHRaised += msg.value;
        contributions[msg.sender] += msg.value;

        // If this is the first investment, deploy the token contract
        if (address(faoToken) == address(0)) {
            faoToken = new FAOToken();
        }

        // Mint 50% of tokens directly to investor
        faoToken.mint(msg.sender, tokenAmount);

        emit ICOInvestment(msg.sender, msg.value, tokenAmount);
    }

    function getRefund() external nonReentrant {
        require(!icoComplete, "ICO is complete");
        require(block.timestamp < startTime + ICO_DURATION, "ICO period ended");

        uint256 amount = contributions[msg.sender];
        require(amount > 0, "No contribution");

        contributions[msg.sender] = 0;
        totalETHRaised -= amount;

        // Burn their tokens before refund
        faoToken.burn(msg.sender, amount * TOKENS_PER_ETH);

        (bool success,) = payable(msg.sender).call{ value: amount }("");
        require(success, "Refund failed");

        emit Refunded(msg.sender, amount);
    }

    // Anyone can complete ICO after 28 days
    function completeICO() external nonReentrant {
        require(!icoComplete, "Already completed");
        require(block.timestamp >= startTime + ICO_DURATION, "ICO period not ended");
        require(address(faoToken) != address(0), "No investments made");

        // Calculate ETH for liquidity pool (40% of raised ETH)
        uint256 liquidityETH = (totalETHRaised * 40) / 100;

        // Initialize token distribution
        faoToken.initialize(
            totalETHRaised,
            treasury,
            options,
            address(this) // Liquidity will be managed by pool contract later
        );

        // Set proposer contract for minting permissions
        faoToken.setProposer(proposer);

        // Transfer ownership to proposer
        faoToken.transferOwnership(proposer);

        // Transfer remaining ETH to treasury
        uint256 treasuryETH = address(this).balance - liquidityETH;
        (bool success1,) = treasury.call{ value: treasuryETH }("");
        require(success1, "Treasury ETH transfer failed");

        // Transfer liquidity ETH to proposer contract for pool setup
        (bool success2,) = proposer.call{ value: liquidityETH }("");
        require(success2, "Liquidity ETH transfer failed");

        icoComplete = true;
        emit ICOCompleted(totalETHRaised, totalETHRaised * TOKENS_PER_ETH);
    }
}
