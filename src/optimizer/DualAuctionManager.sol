// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/FaoInterfaces.sol";

contract DualAuctionManager is ReentrancyGuard {
    // Core state
    IERC20 public immutable faoToken;
    IProposalNFT public immutable proposalNFT;
    address public governor;

    // Regular auction parameters
    uint256 public constant REGULAR_MIN_BID = 100 * 1e18; // 100 FAO
    uint256 public constant REGULAR_START_PRICE = 10_000_000 * 1e18; // 10M FAO

    // Emergency auction parameters
    uint256 public constant EMERGENCY_MIN_BID = 10_000 * 1e18; // 10K FAO
    uint256 public constant EMERGENCY_START_PRICE = 100_000_000 * 1e18; // 100M FAO

    // Common parameters
    uint256 public constant DECAY_DURATION = 5 days;
    uint256 public constant PROPOSAL_SUBMIT_WINDOW = 3 days;

    // Auction state - Regular
    uint256 public regularAuctionStart;
    address public regularBidder;
    bool public regularProposalSubmitted;
    uint256 public nextRegularId = 6; // Start after initial 5 NFTs

    // Auction state - Emergency
    uint256 public emergencyAuctionStart;
    address public emergencyBidder;
    bool public emergencyProposalSubmitted;
    uint256 public nextEmergencyId = 1;

    // Events
    event RegularAuctionStarted(uint256 indexed proposalId, uint256 startTime);
    event EmergencyAuctionStarted(uint256 indexed emergencyId, uint256 startTime);
    event RegularBid(uint256 indexed proposalId, address indexed bidder, uint256 amount);
    event EmergencyBid(uint256 indexed emergencyId, address indexed bidder, uint256 amount);
    event ProposalSubmitted(uint256 indexed proposalId, bool isEmergency);

    constructor(address _faoToken, address _proposalNFT, address _governor) {
        faoToken = IERC20(_faoToken);
        proposalNFT = IProposalNFT(_proposalNFT);
        governor = _governor;

        // Start first regular auction
        _startNewRegularAuction();
        // Emergency auction also starts immediately
        _startNewEmergencyAuction();
    }

    // Regular auction functions
    function _startNewRegularAuction() internal {
        regularAuctionStart = block.timestamp;
        regularBidder = address(0);
        regularProposalSubmitted = false;
        emit RegularAuctionStarted(nextRegularId, regularAuctionStart);
    }

    function getRegularPrice() public view returns (uint256) {
        if (block.timestamp <= regularAuctionStart) return REGULAR_START_PRICE;

        uint256 elapsed = block.timestamp - regularAuctionStart;
        if (elapsed >= DECAY_DURATION) return REGULAR_MIN_BID;

        // Linear decay between start and min price over decay duration
        uint256 priceDrop = REGULAR_START_PRICE - REGULAR_MIN_BID;
        return REGULAR_START_PRICE - ((priceDrop * elapsed) / DECAY_DURATION);
    }

    function getCurrentPrice() external view returns (uint256) {
        return getRegularPrice();
    }

    // Emergency auction functions
    function _startNewEmergencyAuction() internal {
        emergencyAuctionStart = block.timestamp;
        emergencyBidder = address(0);
        emergencyProposalSubmitted = false;
        emit EmergencyAuctionStarted(nextEmergencyId, emergencyAuctionStart);
    }

    function getEmergencyPrice() public view returns (uint256) {
        if (block.timestamp <= emergencyAuctionStart) return EMERGENCY_START_PRICE;

        uint256 elapsed = block.timestamp - emergencyAuctionStart;
        if (elapsed >= DECAY_DURATION) return EMERGENCY_MIN_BID;

        // Linear decay between start and min price over decay duration
        uint256 priceDrop = EMERGENCY_START_PRICE - EMERGENCY_MIN_BID;
        uint256 currentDrop = (priceDrop * elapsed) / DECAY_DURATION;
        return EMERGENCY_START_PRICE - currentDrop;
    }

    // Bidding functions
    function bidRegular() external nonReentrant {
        require(regularBidder == address(0), "Already has bidder");
        uint256 price = getRegularPrice();

        require(faoToken.transferFrom(msg.sender, governor, price), "Transfer failed");

        regularBidder = msg.sender;
        emit RegularBid(nextRegularId, msg.sender, price);

        // Mint NFT immediately upon winning bid
        proposalNFT.mint(msg.sender, nextRegularId);
    }

    function bidEmergency() external nonReentrant {
        require(emergencyBidder == address(0), "Already has bidder");
        uint256 price = getEmergencyPrice();

        require(faoToken.transferFrom(msg.sender, governor, price), "Transfer failed");

        emergencyBidder = msg.sender;
        emit EmergencyBid(nextEmergencyId, msg.sender, price);

        // Mint emergency NFT immediately upon winning bid
        proposalNFT.mintEmergency(msg.sender, nextEmergencyId);
    }

    // Proposal submission tracking
    function markRegularProposalSubmitted() external {
        require(msg.sender == governor, "Not governor");
        require(regularBidder != address(0), "No bidder");
        require(!regularProposalSubmitted, "Already submitted");

        regularProposalSubmitted = true;
        nextRegularId++;
        _startNewRegularAuction();

        emit ProposalSubmitted(nextRegularId - 1, false);
    }

    function markEmergencyProposalSubmitted() external {
        require(msg.sender == governor, "Not governor");
        require(emergencyBidder != address(0), "No bidder");
        require(!emergencyProposalSubmitted, "Already submitted");

        emergencyProposalSubmitted = true;
        nextEmergencyId++;
        _startNewEmergencyAuction();

        emit ProposalSubmitted(nextEmergencyId - 1, true);
    }
}
