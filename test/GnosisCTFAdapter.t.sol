// test/GnosisCTFAdapter.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/gnosis/GnosisCTFAdapter.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockConditionalTokens.sol";
import "../src/mocks/MockWrapped1155Factory.sol";

contract GnosisCTFAdapterTest is Test {
    GnosisCTFAdapter public adapter;
    MockConditionalTokens public conditionalTokens;
    MockWrapped1155Factory public wrapped1155Factory;
    MockERC20 public collateralToken;

    address public owner;
    address public user;

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        // Deploy mocks
        collateralToken = new MockERC20("Test Token", "TEST");
        conditionalTokens = new MockConditionalTokens();
        wrapped1155Factory = new MockWrapped1155Factory();

        // Deploy adapter
        adapter = new GnosisCTFAdapter(address(conditionalTokens), address(wrapped1155Factory));

        // Setup test tokens
        vm.startPrank(user);
        collateralToken.mint(user, 1000 ether);
        collateralToken.approve(address(adapter), 1000 ether);
        vm.stopPrank();
    }

    function testSplitTokensBinaryOutcome() public {
        vm.startPrank(user);

        uint256 amount = 100 ether;
        bytes32 questionId = keccak256("Did it rain today?");
        bytes32 conditionId = conditionalTokens.getConditionId(owner, questionId, 2);

        conditionalTokens.prepareCondition(owner, questionId, 2);

        address[] memory wrappedTokens = adapter.splitCollateralTokens(
            IERC20(collateralToken), // Cast to IERC20
            conditionId,
            amount,
            2
        );

        assertEq(wrappedTokens.length, 2, "Should return two token addresses");
        assertEq(
            collateralToken.balanceOf(address(conditionalTokens)),
            amount,
            "Conditional tokens should receive collateral"
        );

        vm.stopPrank();
    }

    function testRevertInvalidOutcomeCount() public {
        vm.startPrank(user);

        bytes32 questionId = keccak256("Did it rain today?");
        bytes32 conditionId = conditionalTokens.getConditionId(owner, questionId, 1);

        // Change this line to properly expect the custom error with parameter
        vm.expectRevert(abi.encodeWithSelector(GnosisCTFAdapter.InvalidOutcomeCount.selector, 1));

        adapter.splitCollateralTokens(IERC20(collateralToken), conditionId, 100 ether, 1);

        vm.stopPrank();
    }

    function testRedeemPositions() public {
        vm.startPrank(user);

        uint256 amount = 100 ether;
        bytes32 questionId = keccak256("Did it rain today?");
        bytes32 conditionId = conditionalTokens.getConditionId(owner, questionId, 2);

        conditionalTokens.prepareCondition(owner, questionId, 2);

        // Split tokens
        adapter.splitCollateralTokens(
            IERC20(collateralToken), // Cast to IERC20
            conditionId,
            amount,
            2
        );

        // Set condition as resolved
        conditionalTokens.setPayoutDenominator(conditionId, 2);

        // Redeem positions
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount;

        uint256 payout = adapter.redeemPositions(
            IERC20(collateralToken), // Cast to IERC20
            conditionId,
            amounts,
            2
        );

        assertGt(payout, 0, "Should receive payout");

        vm.stopPrank();
    }

    function testMultipleOutcomes() public {
        vm.startPrank(user);

        uint256 amount = 100 ether;
        bytes32 questionId = keccak256("What will be the weather?"); // Sunny, Rainy, Cloudy
        bytes32 conditionId = conditionalTokens.getConditionId(owner, questionId, 3);

        conditionalTokens.prepareCondition(owner, questionId, 3);

        address[] memory wrappedTokens = adapter.splitCollateralTokens(IERC20(collateralToken), conditionId, amount, 3);

        assertEq(wrappedTokens.length, 3, "Should return three token addresses");
        assertEq(wrappedTokens[0] != wrappedTokens[1], true, "Tokens should be different");
        assertEq(
            collateralToken.balanceOf(address(conditionalTokens)),
            amount,
            "Conditional tokens should receive collateral"
        );

        vm.stopPrank();
    }

    function testRevertConditionNotResolved() public {
        vm.startPrank(user);

        uint256 amount = 100 ether;
        bytes32 questionId = keccak256("Did it rain today?");
        bytes32 conditionId = conditionalTokens.getConditionId(owner, questionId, 2);

        conditionalTokens.prepareCondition(owner, questionId, 2);

        // Split tokens
        adapter.splitCollateralTokens(IERC20(collateralToken), conditionId, amount, 2);

        // Try to redeem without resolution
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount;

        vm.expectRevert(GnosisCTFAdapter.ConditionNotResolved.selector);
        adapter.redeemPositions(IERC20(collateralToken), conditionId, amounts, 2);

        vm.stopPrank();
    }

    function testGetWrappedTokens() public view {
        bytes32 questionId = keccak256("Did it rain today?");
        bytes32 conditionId = conditionalTokens.getConditionId(owner, questionId, 2);

        address[] memory wrappedTokens = adapter.getWrappedTokens(IERC20(collateralToken), conditionId, 2);

        assertEq(wrappedTokens.length, 2, "Should return two addresses");
        assertEq(wrappedTokens[0] != wrappedTokens[1], true, "Addresses should be different");
    }

    function testSplitMaxOutcomes() public {
        vm.startPrank(user);

        uint256 amount = 100 ether;
        bytes32 questionId = keccak256("Multiple choice question");
        bytes32 conditionId = conditionalTokens.getConditionId(owner, questionId, 256);

        conditionalTokens.prepareCondition(owner, questionId, 256);

        address[] memory wrappedTokens =
            adapter.splitCollateralTokens(IERC20(collateralToken), conditionId, amount, 256);

        assertEq(wrappedTokens.length, 256, "Should handle maximum outcomes");
        vm.stopPrank();
    }

    function testRedeemZeroAmounts() public {
        vm.startPrank(user);

        bytes32 questionId = keccak256("Test zero amounts");
        bytes32 conditionId = conditionalTokens.getConditionId(owner, questionId, 2);

        conditionalTokens.prepareCondition(owner, questionId, 2);
        conditionalTokens.setPayoutDenominator(conditionId, 2);

        uint256[] memory amounts = new uint256[](2);
        // Both amounts are 0
        amounts[0] = 0;
        amounts[1] = 0;

        uint256 payout = adapter.redeemPositions(IERC20(collateralToken), conditionId, amounts, 2);

        assertEq(payout, 0, "Should handle zero amounts");
        vm.stopPrank();
    }
}
