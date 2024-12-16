// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICTFAdapter.sol";
import "./interfaces/IBalancerPoolWrapper.sol";

contract FutarchyPoolManager {

    ICTFAdapter public immutable ctfAdapter;
    IBalancerPoolWrapper public immutable balancerWrapper;

    IERC20 public immutable outcomeToken;
    IERC20 public immutable moneyToken;

    bool public useEnhancedSecurity;
    address public admin;
    address public basePool;

    struct ConditionalPools {
        address yesPool;
        address noPool;
        bool isActive;
    }

    struct ConditionTokens {
        address outcomeYesToken;
        address outcomeNoToken;
        address moneyYesToken;
        address moneyNoToken;
    }

    mapping(bytes32 => ConditionalPools) public conditionPools;
    mapping(bytes32 => ConditionTokens) public conditionTokens;
    mapping(bytes32 => bool) public allowedSplits;

    // Errors
    error ConditionAlreadyActive();
    error ConditionNotActive();
    error Unauthorized();
    error SplitNotAllowed();

    // Events
    event SplitAllowed(address baseToken, address splitToken1, address splitToken2);
    event SplitPerformed(address baseToken, address yesToken, address noToken);
    event MergePerformed(address baseToken, address winningOutcomeToken);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    constructor(
        address _ctfAdapter,
        address _balancerWrapper,
        address _outcomeToken,
        address _moneyToken,
        bool _useEnhancedSecurity,
        address _admin
    ) {
        ctfAdapter = ICTFAdapter(_ctfAdapter);
        balancerWrapper = IBalancerPoolWrapper(_balancerWrapper);
        outcomeToken = IERC20(_outcomeToken);
        moneyToken = IERC20(_moneyToken);
        useEnhancedSecurity = _useEnhancedSecurity;
        admin = _admin;
    }

    function addAllowedSplit(address baseToken, address splitToken1, address splitToken2) external onlyAdmin {
        allowedSplits[keccak256(abi.encodePacked(baseToken, splitToken1, splitToken2))] = true;
        emit SplitAllowed(baseToken, splitToken1, splitToken2);
    }

    function createBasePool(uint256 outcomeAmount, uint256 moneyAmount, uint256 weight) external returns (address) {
        outcomeToken.safeTransferFrom(msg.sender, address(this), outcomeAmount);
        moneyToken.safeTransferFrom(msg.sender, address(this), moneyAmount);

        outcomeToken.safeApprove(address(balancerWrapper), outcomeAmount);
        moneyToken.safeApprove(address(balancerWrapper), moneyAmount);

        basePool = balancerWrapper.createPool(address(outcomeToken), address(moneyToken), weight);
        balancerWrapper.addLiquidity(basePool, outcomeAmount, moneyAmount);
        return basePool;
    }

    function splitOnCondition(bytes32 conditionId, uint256 baseAmount)
        external
        returns (address yesPool, address noPool)
    {
        if (conditionPools[conditionId].isActive) revert ConditionAlreadyActive();

        uint256 beforeOutBase = outcomeToken.balanceOf(address(this));
        uint256 beforeMonBase = moneyToken.balanceOf(address(this));

        (uint256 outAmt, uint256 monAmt) = balancerWrapper.removeLiquidity(basePool, baseAmount);

        (address outYes, address outNo, address monYes, address monNo) = _doSplit(conditionId, outAmt, monAmt);
        if (useEnhancedSecurity) {
            _enforceAllowedSplit(address(outcomeToken), outYes, outNo);
            _enforceAllowedSplit(address(moneyToken), monYes, monNo);

            _verifySplitDimension(
                beforeOutBase,
                outcomeToken.balanceOf(address(this)),
                IERC20(outYes).balanceOf(address(this)),
                IERC20(outNo).balanceOf(address(this))
            );

            _verifySplitDimension(
                beforeMonBase,
                moneyToken.balanceOf(address(this)),
                IERC20(monYes).balanceOf(address(this)),
                IERC20(monNo).balanceOf(address(this))
            );
        }

        yesPool = balancerWrapper.createPool(outYes, monYes, 500000);
        noPool = balancerWrapper.createPool(outNo, monNo, 500000);

        _storeConditionPools(conditionId, yesPool, noPool);
        _storeConditionTokens(conditionId, outYes, outNo, monYes, monNo);

        emit SplitPerformed(address(outcomeToken), outYes, outNo);
        emit SplitPerformed(address(moneyToken), monYes, monNo);

        return (yesPool, noPool);
    }

    function mergeAfterSettlement(bytes32 conditionId) external {
        ConditionalPools storage pools = conditionPools[conditionId];
        if (!pools.isActive) revert ConditionNotActive();

        ConditionTokens memory ct = conditionTokens[conditionId];

        uint256 beforeOutBase = outcomeToken.balanceOf(address(this));
        uint256 beforeMonBase = moneyToken.balanceOf(address(this));
        uint256 beforeOutYes = IERC20(ct.outcomeYesToken).balanceOf(address(this));
        uint256 beforeOutNo = IERC20(ct.outcomeNoToken).balanceOf(address(this));
        uint256 beforeMonYes = IERC20(ct.moneyYesToken).balanceOf(address(this));
        uint256 beforeMonNo = IERC20(ct.moneyNoToken).balanceOf(address(this));

        (uint256 outAmt, uint256 monAmt) = balancerWrapper.removeLiquidity(pools.yesPool, type(uint256).max);

        // Redeem
        IERC20(ct.outcomeYesToken).approve(address(ctfAdapter), outAmt);
        IERC20(ct.moneyYesToken).approve(address(ctfAdapter), monAmt);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = outAmt;
        ctfAdapter.redeemPositions(outcomeToken, conditionId, amounts, 2);

        amounts[1] = monAmt;
        ctfAdapter.redeemPositions(moneyToken, conditionId, amounts, 2);

        uint256 afterOutBase = outcomeToken.balanceOf(address(this));
        uint256 afterMonBase = moneyToken.balanceOf(address(this));
        uint256 afterOutYes = IERC20(ct.outcomeYesToken).balanceOf(address(this));
        uint256 afterOutNo = IERC20(ct.outcomeNoToken).balanceOf(address(this));
        uint256 afterMonYes = IERC20(ct.moneyYesToken).balanceOf(address(this));
        uint256 afterMonNo = IERC20(ct.moneyNoToken).balanceOf(address(this));

        if (useEnhancedSecurity) {
            _verifyMergeAllSides(beforeOutYes, afterOutYes, beforeOutNo, afterOutNo, beforeOutBase, afterOutBase);
            _verifyMergeAllSides(beforeMonYes, afterMonYes, beforeMonNo, afterMonNo, beforeMonBase, afterMonBase);
        }

        uint256 outR = afterOutBase > beforeOutBase ? (afterOutBase - beforeOutBase) : 0;
        uint256 monR = afterMonBase > beforeMonBase ? (afterMonBase - beforeMonBase) : 0;

        outcomeToken.approve(address(balancerWrapper), outR);
        moneyToken.approve(address(balancerWrapper), monR);
        balancerWrapper.addLiquidity(basePool, outR, monR);

        delete conditionPools[conditionId];
        delete conditionTokens[conditionId];

        emit MergePerformed(address(outcomeToken), ct.outcomeYesToken);
        emit MergePerformed(address(moneyToken), ct.moneyYesToken);
    }

    // ------------------ Internal Helper Functions ------------------

    function _doSplit(bytes32 conditionId, uint256 outAmt, uint256 monAmt)
        internal
        returns (address outYes, address outNo, address monYes, address monNo)
    {
        outcomeToken.approve(address(ctfAdapter), outAmt);
        moneyToken.approve(address(ctfAdapter), monAmt);

        address[] memory outC = ctfAdapter.splitCollateralTokens(outcomeToken, conditionId, outAmt, 2);
        address[] memory monC = ctfAdapter.splitCollateralTokens(moneyToken, conditionId, monAmt, 2);

        outYes = outC[1];
        outNo = outC[0];
        monYes = monC[1];
        monNo = monC[0];
    }

    function _storeConditionPools(bytes32 conditionId, address yesPool, address noPool) internal {
        conditionPools[conditionId] = ConditionalPools(yesPool, noPool, true);
    }

    function _storeConditionTokens(bytes32 conditionId, address outYes, address outNo, address monYes, address monNo)
        internal
    {
        ConditionTokens storage ct = conditionTokens[conditionId];
        ct.outcomeYesToken = outYes;
        ct.outcomeNoToken = outNo;
        ct.moneyYesToken = monYes;
        ct.moneyNoToken = monNo;
    }

    function _enforceAllowedSplit(address baseTok, address yesTok, address noTok) internal view {
        if (!allowedSplits[keccak256(abi.encodePacked(baseTok, yesTok, noTok))]) revert SplitNotAllowed();
    }

    // Verification functions

    // On splitting: baseDelta = yesDelta = noDelta
    function _verifySplitDimension(uint256 baseBefore, uint256 baseAfter, uint256 yesAfter, uint256 noAfter)
        internal
        pure
    {
        uint256 baseDelta = baseBefore > baseAfter ? baseBefore - baseAfter : 0;
        uint256 yesDelta = yesAfter;
        uint256 noDelta = noAfter;

        if (baseDelta == 0 || yesDelta != baseDelta || noDelta != baseDelta) {
            revert("Exact split integrity check failed");
        }
    }

    // On merging: max(yesSpent, noSpent) = baseGained
    function _verifyMergeAllSides(
        uint256 yesBefore,
        uint256 yesAfter,
        uint256 noBefore,
        uint256 noAfter,
        uint256 baseBefore,
        uint256 baseAfter
    ) internal pure {
        uint256 yesDelta = yesBefore > yesAfter ? yesBefore - yesAfter : 0;
        uint256 noDelta = noBefore > noAfter ? noBefore - noAfter : 0;
        uint256 maxDelta = yesDelta >= noDelta ? yesDelta : noDelta;
        uint256 baseDelta = baseAfter > baseBefore ? baseAfter - baseBefore : 0;

        if (maxDelta != baseDelta) {
            revert("Exact merge all-sides integrity check failed");
        }
    }
}
