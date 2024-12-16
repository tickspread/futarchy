// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/FaoInterfaces.sol";

contract FAOOracle is ReentrancyGuard {
    IPoolManager public immutable poolManager;

    // Thresholds in basis points
    uint256 public constant NORMAL_THRESHOLD = 100; // 1%
    uint256 public constant CRITICAL_THRESHOLD = 1000; // 10%

    uint256 public constant NORMAL_PERIOD = 7 days;
    uint256 public constant CRITICAL_PERIOD = 28 days;

    // Safety thresholds
    uint256 public constant MAX_PRICE_RATIO = 100; // 100x maximum ratio between YES/NO
    uint256 public constant MIN_VALID_PRICE = 1e6; // Minimum valid price to prevent division by dust

    event AbnormalPrices(uint256 yesPrice, uint256 noPrice, string reason);

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    function queryTWAP(address pool, uint256 period) internal view returns (uint256) {
        require(period <= type(uint32).max, "Period too long");

        uint32[] memory queries = new uint32[](2);
        uint256 endTime = block.timestamp;
        uint256 startTime = endTime - period;

        require(startTime < endTime, "Time overflow");
        queries[0] = uint32(startTime);
        queries[1] = uint32(endTime);

        uint256[] memory prices = IBalancerPool(pool).getTimeWeightedAverage(queries);
        require(prices.length == 2, "Invalid TWAP response");

        return prices[1];
    }

    function validatePrices(uint256 yesPrice, uint256 noPrice) internal pure returns (bool, string memory) {
        // Safety checks - fail proposal if any of these trigger
        if (yesPrice < MIN_VALID_PRICE || noPrice < MIN_VALID_PRICE) {
            return (false, "Price below minimum");
        }

        // Check for extreme price ratios in either direction
        if (yesPrice > noPrice * MAX_PRICE_RATIO || noPrice > yesPrice * MAX_PRICE_RATIO) {
            return (false, "Extreme price ratio");
        }

        return (true, "");
    }

    function checkProposalOutcome(bool isCritical) external view returns (bool) {
        address yesPool = poolManager.getYesPool();
        address noPool = poolManager.getNoPool();
        require(yesPool != address(0) && noPool != address(0), "Pools not found");

        uint256 poolCreationTime = poolManager.getPoolCreationTime();
        uint256 requiredPeriod = isCritical ? CRITICAL_PERIOD : NORMAL_PERIOD;
        require(block.timestamp >= poolCreationTime + requiredPeriod, "Pool too young");

        // Get TWAPs
        uint256 yesPrice = queryTWAP(yesPool, requiredPeriod);
        uint256 noPrice = queryTWAP(noPool, requiredPeriod);

        // Validate prices
        (bool valid,) = validatePrices(yesPrice, noPrice);
        if (!valid) {
            return false;
        }

        // Normal comparison
        uint256 threshold = isCritical ? CRITICAL_THRESHOLD : NORMAL_THRESHOLD;

        if (yesPrice > noPrice) {
            uint256 difference = ((yesPrice - noPrice) * 10000) / noPrice;
            return difference >= threshold;
        }

        return false;
    }

    function getCurrentPrices() external view returns (uint256 yesPrice, uint256 noPrice) {
        address yesPool = poolManager.getYesPool();
        address noPool = poolManager.getNoPool();
        require(yesPool != address(0) && noPool != address(0), "Pools not found");

        // Use small TWAP to smooth very recent manipulation
        uint256 shortPeriod = 1 hours;
        return (queryTWAP(yesPool, shortPeriod), queryTWAP(noPool, shortPeriod));
    }
}
