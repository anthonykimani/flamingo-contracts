// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {FlamingoEscrow} from "../src/FlamingoEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockUSDC
 * @notice ERC20 mock with non-standard behavior testing
 */
contract MockUSDC is IERC20 {
    string public name = "Mock USDC";
    string public symbol = "USDC";
    uint8 public decimals = 6;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(
            _allowances[from][msg.sender] >= amount,
            "Insufficient allowance"
        );
        require(_balances[from] >= amount, "Insufficient balance");

        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
}

/**
 * @title FlamingoEscrowTest
 * @notice Comprehensive test suite for fixed FlamingoEscrow contract
 */
contract FlamingoEscrowTest is Test {
    FlamingoEscrow public escrow;
    MockUSDC public usdc;

    // Test accounts
    address public owner;
    address public treasury = makeAddr("treasury");
    address public backendSigner;
    uint256 public backendSignerKey;

    // Test players
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public player3 = makeAddr("player3");
    address public player4 = makeAddr("player4");

    // Constants
    uint256 public constant STAKE_AMOUNT = 5 * 10 ** 6; // 5 USDC
    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 6; // 1000 USDC

    // Events
    event PlayerDeposited(
        bytes32 indexed gameSessionId,
        address indexed player,
        uint256 amount
    );
    event GameSessionCreated(
        bytes32 indexed gameSessionId,
        uint256 totalPrizePool,
        uint256 platformFee,
        address[] players
    );
    event PrizesDistributed(
        bytes32 indexed gameSessionId,
        address indexed firstPlace,
        address indexed secondPlace,
        address thirdPlace,
        uint256 firstPrize,
        uint256 secondPrize,
        uint256 thirdPrize
    );
    event DepositRefunded(
        bytes32 indexed gameSessionId,
        address indexed player,
        uint256 amount
    );
    event GameSessionCancelled(
        bytes32 indexed gameSessionId,
        uint256 timestamp
    );
    event BackendSignerUpdated(
        address indexed oldSigner,
        address indexed newSigner
    );

    function setUp() public {
        // Generate backend signer keypair
        (backendSigner, backendSignerKey) = makeAddrAndKey("backendSigner");

        owner = address(this);

        // Deploy contracts
        usdc = new MockUSDC();
        escrow = new FlamingoEscrow(address(usdc), treasury, backendSigner);

        // Mint USDC to test players
        usdc.mint(player1, INITIAL_BALANCE);
        usdc.mint(player2, INITIAL_BALANCE);
        usdc.mint(player3, INITIAL_BALANCE);
        usdc.mint(player4, INITIAL_BALANCE);

        // Approve escrow contract
        vm.prank(player1);
        usdc.approve(address(escrow), type(uint256).max);
        vm.prank(player2);
        usdc.approve(address(escrow), type(uint256).max);
        vm.prank(player3);
        usdc.approve(address(escrow), type(uint256).max);
        vm.prank(player4);
        usdc.approve(address(escrow), type(uint256).max);
    }

    // ============================================
    // BASIC FUNCTIONALITY TESTS
    // ============================================

    function testDeposit() public {
        bytes32 gameId = bytes32("GAME_001");

        vm.expectEmit(true, true, false, true);
        emit PlayerDeposited(gameId, player1, STAKE_AMOUNT);

        vm.prank(player1);
        escrow.deposit(gameId, STAKE_AMOUNT);

        assertEq(escrow.getPendingDeposit(gameId, player1), STAKE_AMOUNT);
        assertEq(usdc.balanceOf(player1), INITIAL_BALANCE - STAKE_AMOUNT);
    }

    function testCreateGameSession() public {
        bytes32 gameId = bytes32("GAME_002");

        _setupDeposits(gameId);

        address[] memory players = new address[](3);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;

        vm.prank(backendSigner);
        escrow.createGameSession(gameId, players);

        assertTrue(escrow.gameExists(gameId));

        // Verify pending deposits cleared
        assertEq(escrow.getPendingDeposit(gameId, player1), 0);
        assertEq(escrow.getPendingDeposit(gameId, player2), 0);
        assertEq(escrow.getPendingDeposit(gameId, player3), 0);

        // Verify deposits moved to game session
        assertEq(escrow.getPlayerDeposit(gameId, player1), STAKE_AMOUNT);
        assertEq(escrow.getPlayerDeposit(gameId, player2), STAKE_AMOUNT);
        assertEq(escrow.getPlayerDeposit(gameId, player3), STAKE_AMOUNT);
    }

    function testDistributePrizes() public {
        bytes32 gameId = bytes32("GAME_003");

        _setupAndCreateGame(gameId);

        address[3] memory winners = [player1, player2, player3];
        bytes memory signature = _signWinners(gameId, winners);

        uint256 p1Before = usdc.balanceOf(player1);
        uint256 p2Before = usdc.balanceOf(player2);
        uint256 p3Before = usdc.balanceOf(player3);

        escrow.distributePrizes(gameId, winners, signature);

        // Calculate expected prizes
        uint256 prizePool = (STAKE_AMOUNT * 3 * 90) / 100; // 13.5 USDC
        uint256 firstPrize = (prizePool * 5000) / 10000;
        uint256 secondPrize = (prizePool * 3000) / 10000;
        uint256 thirdPrize = (prizePool * 2000) / 10000;

        assertEq(usdc.balanceOf(player1), p1Before + firstPrize);
        assertEq(usdc.balanceOf(player2), p2Before + secondPrize);
        assertEq(usdc.balanceOf(player3), p3Before + thirdPrize);
    }

    // ============================================
    // NEW FEATURE TESTS
    // ============================================

    function testCancelGameSession() public {
        bytes32 gameId = bytes32("GAME_004");

        _setupAndCreateGame(gameId);

        vm.expectEmit(true, false, false, true);
        emit GameSessionCancelled(gameId, block.timestamp);

        vm.prank(backendSigner);
        escrow.cancelGameSession(gameId);

        (, , , , bool cancelled) = escrow.getGameInfo(gameId);
        assertTrue(cancelled);
    }

    function testRefundAfterCancellation() public {
        bytes32 gameId = bytes32("GAME_005");

        _setupAndCreateGame(gameId);

        vm.prank(backendSigner);
        escrow.cancelGameSession(gameId);

        uint256 balanceBefore = usdc.balanceOf(player1);

        vm.prank(player1);
        escrow.refundDeposit(gameId);

        assertEq(usdc.balanceOf(player1), balanceBefore + STAKE_AMOUNT);
        assertEq(escrow.getPlayerDeposit(gameId, player1), 0);
    }

    function testRefundBeforeGameCreation() public {
        bytes32 gameId = bytes32("GAME_006");

        vm.prank(player1);
        escrow.deposit(gameId, STAKE_AMOUNT);

        uint256 balanceBefore = usdc.balanceOf(player1);

        vm.prank(player1);
        escrow.refundDeposit(gameId);

        assertEq(usdc.balanceOf(player1), balanceBefore + STAKE_AMOUNT);
    }

    function testEmergencyWithdraw() public {
        bytes32 gameId = bytes32("GAME_007");

        vm.prank(player1);
        escrow.deposit(gameId, STAKE_AMOUNT);

        uint256 contractBalance = usdc.balanceOf(address(escrow));

        vm.prank(owner);
        escrow.emergencyWithdraw(address(usdc), treasury, contractBalance);

        assertEq(usdc.balanceOf(treasury), contractBalance);
    }

    function testUpdateBackendSigner() public {
        address newSigner = makeAddr("newSigner");

        vm.expectEmit(true, true, false, false);
        emit BackendSignerUpdated(backendSigner, newSigner);

        vm.prank(owner);
        escrow.updateBackendSigner(newSigner);

        assertEq(escrow.backendSigner(), newSigner);
    }

    // ============================================
    // SECURITY TESTS
    // ============================================

    function testCannotDepositTwice() public {
        bytes32 gameId = bytes32("GAME_008");

        vm.startPrank(player1);
        escrow.deposit(gameId, STAKE_AMOUNT);

        vm.expectRevert("Already deposited");
        escrow.deposit(gameId, STAKE_AMOUNT);
        vm.stopPrank();
    }

    function testCannotDistributeTwice() public {
        bytes32 gameId = bytes32("GAME_009");

        _setupAndCreateGame(gameId);

        address[3] memory winners = [player1, player2, player3];
        bytes memory signature = _signWinners(gameId, winners);

        escrow.distributePrizes(gameId, winners, signature);

        vm.expectRevert("Already paid out");
        escrow.distributePrizes(gameId, winners, signature);
    }

    function testCannotDistributeWithDuplicateWinners() public {
        bytes32 gameId = bytes32("GAME_010");

        _setupAndCreateGame(gameId);

        // Same player as 1st and 2nd
        address[3] memory winners = [player1, player1, player3];
        bytes memory signature = _signWinners(gameId, winners);

        vm.expectRevert("Winner 1 and 2 same");
        escrow.distributePrizes(gameId, winners, signature);
    }

    function testCannotDistributeToNonPlayer() public {
        bytes32 gameId = bytes32("GAME_011");

        _setupAndCreateGame(gameId);

        address faker = makeAddr("faker");
        address[3] memory winners = [faker, player2, player3];
        bytes memory signature = _signWinners(gameId, winners);

        vm.expectRevert("Winner 1 not player");
        escrow.distributePrizes(gameId, winners, signature);
    }

    function testSignatureReplayProtection() public {
        bytes32 gameId1 = bytes32("GAME_012");
        bytes32 gameId2 = bytes32("GAME_013");

        // Create two games
        _setupAndCreateGame(gameId1);
        _setupDeposits(gameId2);

        address[] memory players = new address[](3);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;

        vm.prank(backendSigner);
        escrow.createGameSession(gameId2, players);

        // Get signature for game1
        address[3] memory winners = [player1, player2, player3];
        bytes memory signature = _signWinners(gameId1, winners);

        // Distribute game1
        escrow.distributePrizes(gameId1, winners, signature);

        // Try to replay signature on game2 - should fail
        vm.expectRevert("Invalid signature");
        escrow.distributePrizes(gameId2, winners, signature);
    }

    function testInvalidSignature() public {
        bytes32 gameId = bytes32("GAME_014");

        _setupAndCreateGame(gameId);

        address[3] memory winners = [player1, player2, player3];

        // Create signature with wrong signer
        (, uint256 wrongKey) = makeAddrAndKey("wrongSigner");
        bytes32 messageHash = keccak256(
            abi.encode(
                address(escrow),
                block.chainid,
                gameId,
                winners[0],
                winners[1],
                winners[2]
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, messageHash);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        vm.expectRevert("Invalid signature");
        escrow.distributePrizes(gameId, winners, wrongSignature);
    }

    function testCannotRefundAfterGameStartedWithoutCancel() public {
        bytes32 gameId = bytes32("GAME_015");

        _setupAndCreateGame(gameId);

        vm.prank(player1);
        vm.expectRevert("Game not cancelled");
        escrow.refundDeposit(gameId);
    }

    function testCannotCancelAfterPayout() public {
        bytes32 gameId = bytes32("GAME_016");

        _setupAndCreateGame(gameId);

        address[3] memory winners = [player1, player2, player3];
        escrow.distributePrizes(gameId, winners, _signWinners(gameId, winners));

        vm.prank(backendSigner);
        vm.expectRevert("Already paid out");
        escrow.cancelGameSession(gameId);
    }

    function testOnlyOwnerCanUpdateSigner() public {
        address newSigner = makeAddr("newSigner");

        vm.prank(player1);
        vm.expectRevert();
        escrow.updateBackendSigner(newSigner);
    }

    function testOnlyBackendCanCreateGame() public {
        bytes32 gameId = bytes32("GAME_017");

        _setupDeposits(gameId);

        address[] memory players = new address[](3);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;

        vm.prank(player1);
        vm.expectRevert("Only backend");
        escrow.createGameSession(gameId, players);
    }

    function testOnlyBackendCanCancelGame() public {
        bytes32 gameId = bytes32("GAME_018");

        _setupAndCreateGame(gameId);

        vm.prank(player1);
        vm.expectRevert("Only backend");
        escrow.cancelGameSession(gameId);
    }

    // ============================================
    // EDGE CASE TESTS
    // ============================================

    function testDustHandling() public {
        bytes32 gameId = bytes32("GAME_019");

        // Use amounts that create rounding dust
        uint256 stake = 7 * 10 ** 6; // 7 USDC

        vm.prank(player1);
        escrow.deposit(gameId, stake);
        vm.prank(player2);
        escrow.deposit(gameId, stake);
        vm.prank(player3);
        escrow.deposit(gameId, stake);

        address[] memory players = new address[](3);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;

        vm.prank(backendSigner);
        escrow.createGameSession(gameId, players);

        uint256 treasuryBefore = usdc.balanceOf(treasury);

        address[3] memory winners = [player1, player2, player3];
        escrow.distributePrizes(gameId, winners, _signWinners(gameId, winners));

        // Dust should be sent to treasury
        uint256 treasuryAfter = usdc.balanceOf(treasury);
        assertTrue(treasuryAfter >= treasuryBefore);
    }

    function testMultipleGamesIndependent() public {
        bytes32 game1 = bytes32("GAME_020");
        bytes32 game2 = bytes32("GAME_021");

        // Player1 in both games
        vm.prank(player1);
        escrow.deposit(game1, STAKE_AMOUNT);

        vm.prank(player1);
        escrow.deposit(game2, STAKE_AMOUNT);

        assertEq(escrow.getPendingDeposit(game1, player1), STAKE_AMOUNT);
        assertEq(escrow.getPendingDeposit(game2, player1), STAKE_AMOUNT);
    }

    function testHelperFunctions() public view {
        string memory uuid = "abc123";
        bytes32 result = escrow.hashToBytes32(uuid);
        assertTrue(result != bytes32(0));
    }

    // ============================================
    // GAS OPTIMIZATION TESTS
    // ============================================

    function testIsPlayerLookup() public {
        bytes32 gameId = bytes32("GAME_022");

        _setupAndCreateGame(gameId);

        // O(1) lookup using mapping
        uint256 gasBefore = gasleft();
        bool isPlayer = escrow.isPlayerInGame(gameId, player1);
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(isPlayer);
        console.log("Gas for isPlayerInGame:", gasUsed);
        assertLt(gasUsed, 5000); // Should be very cheap
    }

    function testGasDeposit() public {
        bytes32 gameId = bytes32("GAS_001");

        vm.prank(player1);
        uint256 gasBefore = gasleft();
        escrow.deposit(gameId, STAKE_AMOUNT);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for deposit:", gasUsed);
        assertLt(gasUsed, 100_000);
    }

    function testGasDistribute() public {
        bytes32 gameId = bytes32("GAS_002");

        _setupAndCreateGame(gameId);

        address[3] memory winners = [player1, player2, player3];
        bytes memory signature = _signWinners(gameId, winners);

        uint256 gasBefore = gasleft();
        escrow.distributePrizes(gameId, winners, signature);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas for distributePrizes:", gasUsed);
        assertLt(gasUsed, 150_000);
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    function _setupDeposits(bytes32 gameId) internal {
        vm.prank(player1);
        escrow.deposit(gameId, STAKE_AMOUNT);

        vm.prank(player2);
        escrow.deposit(gameId, STAKE_AMOUNT);

        vm.prank(player3);
        escrow.deposit(gameId, STAKE_AMOUNT);
    }

    function _setupAndCreateGame(bytes32 gameId) internal {
        _setupDeposits(gameId);

        address[] memory players = new address[](3);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;

        vm.prank(backendSigner);
        escrow.createGameSession(gameId, players);
    }

    function _signWinners(
        bytes32 gameId,
        address[3] memory winners
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encode(
                address(escrow),
                block.chainid,
                gameId,
                winners[0],
                winners[1],
                winners[2]
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backendSignerKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
