// test/FutarchyPoolManager.t.sol
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FutarchyPoolManager.sol";
import "../src/gnosis/GnosisCTFAdapter.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockBalancerPoolWrapper.sol";
import "../src/mocks/MockConditionalTokens.sol";
import "../src/mocks/MockWrapped1155Factory.sol";

contract FutarchyPoolManagerTest is Test {
    FutarchyPoolManager public manager;
    GnosisCTFAdapter public ctfAdapter;
    MockBalancerPoolWrapper public balancerWrapper;
    MockERC20 public outcomeToken;
    MockERC20 public moneyToken;

    address public owner;
    address public user;

    // test/FutarchyPoolManager.t.sol
    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        // Deploy tokens
        outcomeToken = new MockERC20("Outcome Token", "OUT");
        moneyToken = new MockERC20("Money Token", "MON");

        // Deploy mock conditional tokens and wrapper
        MockConditionalTokens conditionalTokens = new MockConditionalTokens();
        MockWrapped1155Factory wrappedFactory = new MockWrapped1155Factory();

        // Deploy adapters/wrappers
        ctfAdapter = new GnosisCTFAdapter(address(conditionalTokens), address(wrappedFactory));
        balancerWrapper = new MockBalancerPoolWrapper();

        // Deploy manager
        manager = new FutarchyPoolManager(
            address(ctfAdapter),
            address(balancerWrapper),
            address(outcomeToken),
            address(moneyToken),
            false, // _useEnhancedSecurity
            owner // use owner for admin
        );

        // Setup initial tokens
        vm.startPrank(user);
        outcomeToken.mint(user, 1000 ether);
        moneyToken.mint(user, 1000 ether);
        outcomeToken.approve(address(manager), type(uint256).max);
        moneyToken.approve(address(manager), type(uint256).max);
        vm.stopPrank();
    }

    function testCreateBasePool() public {
        vm.startPrank(user);

        uint256 outcomeAmount = 100 ether;
        uint256 moneyAmount = 100 ether;
        uint256 weight = 500000; // 50-50

        address pool = manager.createBasePool(outcomeAmount, moneyAmount, weight);

        assertEq(pool != address(0), true, "Pool should be created");
        assertEq(
            outcomeToken.balanceOf(address(balancerWrapper)), outcomeAmount, "Wrapper should receive outcome tokens"
        );
        assertEq(moneyToken.balanceOf(address(balancerWrapper)), moneyAmount, "Wrapper should receive money tokens");

        vm.stopPrank();
    }

    function testSplitOnCondition() public {
        vm.startPrank(user);

        // First create base pool
        uint256 outcomeAmount = 100 ether;
        uint256 moneyAmount = 100 ether;
        manager.createBasePool(outcomeAmount, moneyAmount, 500000);

        // Create condition
        bytes32 conditionId = bytes32(uint256(1)); // Mock condition ID
        uint256 baseAmount = 80 ether; // 80% of liquidity

        (address yesPool, address noPool) = manager.splitOnCondition(conditionId, baseAmount);

        assertEq(yesPool != address(0), true, "YES pool should be created");
        assertEq(noPool != address(0), true, "NO pool should be created");

        vm.stopPrank();
    }

    function testRevertSplitTwice() public {
        vm.startPrank(user);

        // Create base pool
        manager.createBasePool(100 ether, 100 ether, 500000);

        // Split first time
        bytes32 conditionId = bytes32(uint256(1));
        manager.splitOnCondition(conditionId, 80 ether);

        // Try to split again with same condition
        vm.expectRevert(FutarchyPoolManager.ConditionAlreadyActive.selector);
        manager.splitOnCondition(conditionId, 80 ether);

        vm.stopPrank();
    }

    // Add more tests...
}
