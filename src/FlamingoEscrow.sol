// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FlamingoEscrow
 * @notice Secure escrow for quiz game deposits and prize distribution
 * @dev Backend handles matchmaking; contract handles money safety
 * 
 */
contract FlamingoEscrow is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    
    // ============================================
    // IMMUTABLE STATE
    // ============================================
    
    IERC20 public immutable USDC;
    address public immutable PLATFORM_TREASURY;
    uint256 public constant PLATFORM_FEE_PERCENT = 10;
    
    // Prize distribution (basis points: 10000 = 100%)
    uint256 public constant FIRST_PLACE_BP = 5000;   // 50%
    uint256 public constant SECOND_PLACE_BP = 3000;  // 30%
    uint256 public constant THIRD_PLACE_BP = 2000;   // 20%
    
    // Signature malleability protection (EIP-2)
    uint256 private constant SIGNATURE_S_VALUE_MAX = 
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;
    
    // ============================================
    // MUTABLE STATE
    // ============================================
    
    address public backendSigner;
    
    // Game state
    struct GameSession {
        uint256 prizePool;
        uint256 platformFee;
        address[] players;
        mapping(address => bool) isPlayer;  // O(1) lookup
        mapping(address => uint256) deposits; // Per-player deposits
        bool paidOut;
        bool cancelled;
        uint256 createdAt;
        uint256 paidOutAt;
    }
    
    // Use bytes32 instead of string for gas efficiency
    mapping(bytes32 => GameSession) public games;
    mapping(bytes32 => bool) public gameExists;
    
    // Track player deposits before game creation (can be refunded)
    mapping(bytes32 => mapping(address => uint256)) public pendingDeposits;
    
    // ============================================
    // EVENTS
    // ============================================
    
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
    
    event EmergencyWithdraw(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    
    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    constructor(
        address _usdc,
        address _treasury,
        address _backendSigner
    ) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC");
        require(_treasury != address(0), "Invalid treasury");
        require(_backendSigner != address(0), "Invalid signer");
        
        USDC = IERC20(_usdc);
        PLATFORM_TREASURY = _treasury;
        backendSigner = _backendSigner;
    }
    
    // ============================================
    // PLAYER FUNCTIONS
    // ============================================
    
    /**
     * @notice Player deposits funds for a game session
     * @param gameSessionId Unique game identifier (bytes32 for gas efficiency)
     * @param amount Amount to deposit (in USDC with 6 decimals)
     * @dev Uses SafeERC20 to handle non-standard token implementations
     */
    function deposit(bytes32 gameSessionId, uint256 amount) 
        external 
        nonReentrant 
    {
        require(amount > 0, "Invalid amount");
        require(pendingDeposits[gameSessionId][msg.sender] == 0, "Already deposited");
        require(!gameExists[gameSessionId], "Game already created");
        
        // Use SafeERC20 - handles tokens that don't return bool
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        
        pendingDeposits[gameSessionId][msg.sender] = amount;
        
        emit PlayerDeposited(gameSessionId, msg.sender, amount);
    }
    
    /**
     * @notice Player withdraws deposit if game hasn't started or was cancelled
     * @param gameSessionId Game identifier
     * @dev Fixed: Now works both before game creation and after cancellation
     */
    function refundDeposit(bytes32 gameSessionId) 
        external 
        nonReentrant 
    {
        uint256 amount;
        
        if (!gameExists[gameSessionId]) {
            // Game not created yet - refund pending deposit
            amount = pendingDeposits[gameSessionId][msg.sender];
            require(amount > 0, "No deposit");
            
            pendingDeposits[gameSessionId][msg.sender] = 0;
        } else {
            // Game created but cancelled - refund from game session
            GameSession storage game = games[gameSessionId];
            require(game.cancelled, "Game not cancelled");
            require(!game.paidOut, "Already paid out");
            
            amount = game.deposits[msg.sender];
            require(amount > 0, "No deposit");
            
            game.deposits[msg.sender] = 0;
        }
        
        USDC.safeTransfer(msg.sender, amount);
        
        emit DepositRefunded(gameSessionId, msg.sender, amount);
    }
    
    // ============================================
    // BACKEND FUNCTIONS
    // ============================================
    
    /**
     * @notice Backend creates game session after matching players
     * @param gameSessionId Unique game identifier
     * @param players Array of player addresses who deposited
     * @dev Fixed: Clears pending deposits and stores in game session
     */
    function createGameSession(
        bytes32 gameSessionId,
        address[] calldata players
    ) external {
        require(msg.sender == backendSigner, "Only backend");
        require(!gameExists[gameSessionId], "Game exists");
        require(players.length >= 3, "Need 3+ players");
        
        // Calculate total deposits and validate
        uint256 totalDeposits = 0;
        for (uint256 i = 0; i < players.length; i++) {
            uint256 depositAmount  = pendingDeposits[gameSessionId][players[i]];
            require(depositAmount  > 0, "Player not deposited");
            totalDeposits += depositAmount ;
        }
        
        // Calculate prize pool and platform fee
        uint256 platformFee = (totalDeposits * PLATFORM_FEE_PERCENT) / 100;
        uint256 prizePool = totalDeposits - platformFee;
        
        // Create game session
        GameSession storage game = games[gameSessionId];
        game.prizePool = prizePool;
        game.platformFee = platformFee;
        game.createdAt = block.timestamp;
        
        // Move deposits from pending to game session and build player list
        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];
            uint256 depositAmount = pendingDeposits[gameSessionId][player];
            
            game.players.push(player);
            game.isPlayer[player] = true;
            game.deposits[player] = depositAmount;
            
            // Clear pending deposit (prevents stuck funds)
            pendingDeposits[gameSessionId][player] = 0;
        }
        
        gameExists[gameSessionId] = true;
        
        // Transfer platform fee immediately
        USDC.safeTransfer(PLATFORM_TREASURY, platformFee);
        
        emit GameSessionCreated(gameSessionId, prizePool, platformFee, players);
    }
    
    /**
     * @notice Distribute prizes to winners
     * @param gameSessionId Game identifier
     * @param winners Array of [1st, 2nd, 3rd] place addresses
     * @param signature Backend signature for verification
     * @dev Fixed: Added replay protection, duplicate winner check, s-value validation
     */
    function distributePrizes(
        bytes32 gameSessionId,
        address[3] calldata winners,
        bytes calldata signature
    ) external nonReentrant {
        GameSession storage game = games[gameSessionId];
        
        require(gameExists[gameSessionId], "Game doesn't exist");
        require(!game.paidOut, "Already paid out");
        require(!game.cancelled, "Game cancelled");
        
        // Validate winners are distinct (prevent duplicate winners)
        require(winners[0] != winners[1], "Winner 1 and 2 same");
        require(winners[0] != winners[2], "Winner 1 and 3 same");
        require(winners[1] != winners[2], "Winner 2 and 3 same");
        
        // Verify all winners are valid players (O(1) lookup)
        require(game.isPlayer[winners[0]], "Winner 1 not player");
        require(game.isPlayer[winners[1]], "Winner 2 not player");
        require(game.isPlayer[winners[2]], "Winner 3 not player");
        
        // Verify signature with replay protection
        _verifySignature(gameSessionId, winners, signature);
        
        // Calculate prizes
        uint256 firstPrize = (game.prizePool * FIRST_PLACE_BP) / 10000;
        uint256 secondPrize = (game.prizePool * SECOND_PLACE_BP) / 10000;
        uint256 thirdPrize = (game.prizePool * THIRD_PLACE_BP) / 10000;
        
        // Calculate dust from rounding
        uint256 totalPaid = firstPrize + secondPrize + thirdPrize;
        uint256 dust = game.prizePool - totalPaid;
        
        // Mark as paid BEFORE transfers (CEI pattern)
        game.paidOut = true;
        game.paidOutAt = block.timestamp;
        
        // Transfer prizes using SafeERC20
        USDC.safeTransfer(winners[0], firstPrize);
        USDC.safeTransfer(winners[1], secondPrize);
        USDC.safeTransfer(winners[2], thirdPrize);
        
        // Send dust to platform treasury (if any)
        if (dust > 0) {
            USDC.safeTransfer(PLATFORM_TREASURY, dust);
        }
        
        emit PrizesDistributed(
            gameSessionId,
            winners[0],
            winners[1],
            winners[2],
            firstPrize,
            secondPrize,
            thirdPrize
        );
    }
    
    /**
     * @notice Cancel a game session (allows refunds)
     * @param gameSessionId Game identifier
     * @dev New function: Allows backend to cancel games
     */
    function cancelGameSession(bytes32 gameSessionId) 
        external 
    {
        require(msg.sender == backendSigner, "Only backend");
        require(gameExists[gameSessionId], "Game doesn't exist");
        
        GameSession storage game = games[gameSessionId];
        require(!game.paidOut, "Already paid out");
        require(!game.cancelled, "Already cancelled");
        
        game.cancelled = true;
        
        emit GameSessionCancelled(gameSessionId, block.timestamp);
    }
    
    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================
    
    /**
     * @notice Verify backend signature with replay protection
     * @dev Fixed: Added domain separation, chain ID, and s-value check
     */
    function _verifySignature(
        bytes32 gameSessionId,
        address[3] calldata winners,
        bytes calldata signature
    ) internal view {
        require(signature.length == 65, "Invalid signature length");
        
        // Domain separation: include contract address and chain ID
        // Prevents replay across contracts and chains
        bytes32 messageHash = keccak256(
            abi.encode(  // Use encode instead of encodePacked (no ambiguity)
                address(this),
                block.chainid,
                gameSessionId,
                winners[0],
                winners[1],
                winners[2]
            )
        );
        
        // Ethereum signed message prefix
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        
        // Extract signature components
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        
        // Check s-value to prevent signature malleability (EIP-2)
        require(uint256(s) <= SIGNATURE_S_VALUE_MAX, "Invalid s value");
        
        // Recover signer
        address recovered = ecrecover(ethSignedMessageHash, v, r, s);
        require(recovered == backendSigner, "Invalid signature");
        require(recovered != address(0), "Invalid recovered address");
    }
    
    /**
     * @notice Split signature into r, s, v components
     */
    function _splitSignature(bytes calldata sig)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        
        // Handle v normalization (some wallets use 0/1 instead of 27/28)
        if (v < 27) {
            v += 27;
        }
        
        require(v == 27 || v == 28, "Invalid v value");
    }
    
    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    /**
     * @notice Get game session information
     */
    function getGameInfo(bytes32 gameSessionId)
        external
        view
        returns (
            uint256 prizePool,
            uint256 platformFee,
            address[] memory players,
            bool paidOut,
            bool cancelled
        )
    {
        GameSession storage game = games[gameSessionId];
        return (
            game.prizePool,
            game.platformFee,
            game.players,
            game.paidOut,
            game.cancelled
        );
    }
    
    /**
     * @notice Get pending deposit amount (before game creation)
     */
    function getPendingDeposit(bytes32 gameSessionId, address player)
        external
        view
        returns (uint256)
    {
        return pendingDeposits[gameSessionId][player];
    }
    
    /**
     * @notice Get player deposit in game session (after game creation)
     */
    function getPlayerDeposit(bytes32 gameSessionId, address player)
        external
        view
        returns (uint256)
    {
        return games[gameSessionId].deposits[player];
    }
    
    /**
     * @notice Check if address is a player in game
     */
    function isPlayerInGame(bytes32 gameSessionId, address player)
        external
        view
        returns (bool)
    {
        return games[gameSessionId].isPlayer[player];
    }
    
    // ============================================
    // ADMIN FUNCTIONS
    // ============================================
    
    /**
     * @notice Update backend signer address
     * @param newSigner New backend signer address
     * @dev Fixed: Added event emission and onlyOwner protection
     */
    function updateBackendSigner(address newSigner) 
        external 
        onlyOwner 
    {
        require(newSigner != address(0), "Invalid signer");
        
        address oldSigner = backendSigner;
        backendSigner = newSigner;
        
        emit BackendSignerUpdated(oldSigner, newSigner);
    }
    
    /**
     * @notice Emergency withdraw stuck tokens
     * @param token Token address (use USDC address for USDC)
     * @param to Recipient address
     * @param amount Amount to withdraw
     * @dev New function: Allows owner to rescue stuck funds
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        IERC20(token).safeTransfer(to, amount);
        
        emit EmergencyWithdraw(token, to, amount);
    }
    
    /**
     * @notice Emergency withdraw ETH (if any sent accidentally)
     */
    function emergencyWithdrawETH(address payable to, uint256 amount) 
        external 
        onlyOwner 
    {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(address(this).balance >= amount, "Insufficient balance");
        
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
        
        emit EmergencyWithdraw(address(0), to, amount);
    }
    
    // ============================================
    // HELPER FUNCTIONS
    // ============================================
    
    /**
     * @notice Convert string to bytes32 (for frontend convenience)
     * @dev Useful for converting UUID strings to bytes32
     */
    function stringToBytes32(string memory source) 
        public 
        pure 
        returns (bytes32 result) 
    {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
        
        assembly {
            result := mload(add(source, 32))
        }
    }
    
    /**
     * @notice Hash string to bytes32 (for game IDs longer than 32 bytes)
     */
    function hashToBytes32(string memory source) 
        public 
        pure 
        returns (bytes32) 
    {
        return keccak256(abi.encodePacked(source));
    }
}
