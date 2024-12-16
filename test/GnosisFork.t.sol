pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FutarchyPoolManager.sol";
import "../src/gnosis/GnosisCTFAdapter.sol";
import "../src/pools/BalancerPoolWrapper.sol";
import "../src/mocks/MockERC20.sol";

// test/GnosisFork.t.sol
contract GnosisForkTest is Test {
    uint256 forkId;
    FutarchyPoolManager public manager;
    GnosisCTFAdapter public ctfAdapter;
    BalancerPoolWrapper public balancerWrapper;

    // Real Gnosis mainnet addresses
    address constant GNOSIS_CTF = 0xCeAfDD6bc0bEF976fdCd1112955828E00543c0Ce;
    address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant WRAPPED_1155_FACTORY = 0x191Ccf8B088120082b127002e59d701b684C338c; // Need this address

    // Test tokens (we'll need to deploy these)
    IERC20 public outcomeToken;
    IERC20 public moneyToken;

    function setUp() public {
        forkId = vm.createFork(vm.envString("GNOSIS_RPC_URL"));
        vm.selectFork(forkId);

        // Deploy test tokens
        outcomeToken = new MockERC20("Test Outcome", "OUT");
        moneyToken = new MockERC20("Test Money", "MON");

        // Deploy our wrappers using real contracts
        ctfAdapter = new GnosisCTFAdapter(GNOSIS_CTF, WRAPPED_1155_FACTORY);
        balancerWrapper = new BalancerPoolWrapper(BALANCER_VAULT);

        // Deploy manager
        manager = new FutarchyPoolManager(
            address(ctfAdapter),
            address(balancerWrapper),
            address(outcomeToken),
            address(moneyToken),
            true, // useEnhancedSecurity
            address(this) // admin
        );
    }
}
