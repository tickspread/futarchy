// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FAOToken is ERC20, Ownable {
    address public proposerContract;
    address public ico;
    bool public initialized;

    // Initial distribution addresses
    address public treasuryAddress;
    address public optionsAddress;
    address public liquidityAddress;

    event ProposerSet(address indexed previousProposer, address indexed newProposer);
    event IcoSet(address indexed previousIco, address indexed newIco);
    event Initialized(uint256 investorAmount, uint256 liquidityAmount, uint256 treasuryAmount, uint256 optionsAmount);
    event Burned(address indexed burner, uint256 amount);

    constructor() ERC20("Futarchy Autonomous Organization", "FAO") Ownable(msg.sender) { }

    // Set the ICO contract - can only be done once
    function setIco(address _ico) external onlyOwner {
        require(_ico != address(0), "Zero address");
        require(ico == address(0), "ICO already set");

        emit IcoSet(ico, _ico);
        ico = _ico;
    }

    // Set the proposer contract - can only be done once
    function setProposer(address _proposer) external onlyOwner {
        require(_proposer != address(0), "Zero address");
        require(proposerContract == address(0), "Proposer already set");

        proposerContract = _proposer;
        emit ProposerSet(address(0), _proposer);
    }

    // Initialize token distribution
    function initialize(uint256 ethAmount, address _treasury, address _options, address _liquidity)
        external
        onlyOwner
    {
        require(!initialized, "Already initialized");
        require(_treasury != address(0) && _options != address(0) && _liquidity != address(0), "Zero address");

        // Calculate token amounts based on ETH raised
        // 1 ETH = 10,000 FAO
        uint256 totalSupply = ethAmount * 10000;

        // Distribution:
        // 50% to investors (handled externally)
        // 20% to liquidity pool
        // 10% to treasury
        // 20% to options contract
        uint256 liquidityAmount = (totalSupply * 20) / 100;
        uint256 treasuryAmount = (totalSupply * 10) / 100;
        uint256 optionsAmount = (totalSupply * 20) / 100;

        treasuryAddress = _treasury;
        optionsAddress = _options;
        liquidityAddress = _liquidity;

        // Mint tokens according to distribution
        _mint(liquidityAddress, liquidityAmount);
        _mint(treasuryAddress, treasuryAmount);
        _mint(optionsAddress, optionsAmount);

        initialized = true;

        emit Initialized(
            totalSupply / 2, // investor amount (50%)
            liquidityAmount,
            treasuryAmount,
            optionsAmount
        );
    }

    // Mint function - can only be called by proposer contract
    function mint(address to, uint256 amount) external {
        require(msg.sender == proposerContract, "Only proposer can mint");
        require(to != address(0), "Mint to zero address");
        _mint(to, amount);
    }

    // Burn function - anyone can burn their own tokens
    function burn(address from, uint256 amount) external {
        require(msg.sender == address(ico) || msg.sender == from, "Not authorized to burn");
        _burn(from, amount);
        emit Burned(from, amount);
    }
}
