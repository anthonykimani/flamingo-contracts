// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title FlamingoMatchmaking
 * @notice Manages matchmaking, prize pools, and instant payouts for cash entry games
 * @dev Uses ECDSA for backend signature verification
 */
contract FlamingoMatchmaking is ReentrancyGuard, Pausable {
    using ECDSA for bytes32;
    
    // Immutable configuration
    IERC20 public immutable usdc;
    address public immutable factory;
    address public immutable platformTreasury;
    uint256 public immutable platformFeePercent;
    
    // Backend signer for result verification
    address public backendSigner;
    
    // Game configuration
    uint256 public constant MIN_PLAYERS = 3;
    uint256 public constant MAX_PLAYERS = 10;
    uint256 public constant QUEUE_TIMEOUT = 120; // 2 minutes
    
    // Prize distribution (basis points: 10000 = 100%)
    uint256 public constant FIRST_PLACE_BP = 5000;  // 50%
    uint256 public constant SECOND_PLACE_BP = 3000; // 30%
    uint256 public constant THIRD_PLACE_BP = 2000;  // 20%
    
    // Matchmaking queue structure
    struct MatchQueue {
        uint256 stakeAmount;
        address[] players;
        string[] playerNames;
        mapping(address => bool) hasJoined;
        uint256 createdAt;
        bool gameStarted;
        string gameSessionId;
    }
    
    // Active game structure
    struct ActiveGame {
        uint256 stakeAmount;
        address[] players;
        uint256 prizePool;
        uint256 platformFee;
        bool completed;
        bool paidOut;
        uint256 startedAt;
        uint256 completedAt;
    }
    
    // Storage
    mapping(uint256 => MatchQueue[]) private queues; // stakeAmount => queues
    mapping(address => uint256) public playerCurrentStake; // player => stake they're queued for
    mapping(string => ActiveGame) public activeGames; // gameSessionId => game
    mapping(string => bool) public gameSessionExists; // prevent replay
    
    // Stats
    uint256 public totalGamesCompleted;
    uint256 public totalPrizesDistributed;
    
    // Events
    event PlayerJoinedQueue(
        address indexed player,
        string playerName,
        uint256 stakeAmount,
        uint256 queueIndex,
        uint256 playersInQueue
    );
    
    event PlayerLeftQueue(
        address indexed player,
        uint256 stakeAmount,
        uint256 refundAmount
    );
    
    event GameMatched(
        string indexed gameSessionId,
        uint256 stakeAmount,
        address[] players,
        string[] playerNames,
        uint256 prizePool,
        uint256 platformFee
    );
    
    event GameCompleted(
        string indexed gameSessionId,
        address indexed firstPlace,
        address indexed secondPlace,
        address thirdPlace,
        uint256 firstPrize,
        uint256 secondPrize,
        uint256 thirdPrize
    );
    
    event BackendSignerUpdated(address oldSigner, address newSigner);
    
    constructor(
        address _usdc,
        address _factory,
        address _platformTreasury,
        uint256 _platformFeePercent,
        address _backendSigner
    ) {
        require(_usdc != address(0), "Invalid USDC");
        require(_factory != address(0), "Invalid factory");
        require(_platformTreasury != address(0), "Invalid treasury");
        require(_backendSigner != address(0), "Invalid signer");
        require(_platformFeePercent <= 20, "Fee too high");
        
        usdc = IERC20(_usdc);
        factory = _factory;
        platformTreasury = _platformTreasury;
        platformFeePercent = _platformFeePercent;
        backendSigner = _backendSigner;
    }
    
    /**
     * @notice Join matchmaking queue for a specific stake amount
     * @param stakeAmount Amount to wager (in USDC, 6 decimals)
     * @param playerName Player's display name
     */
    function joinMatchmaking(uint256 stakeAmount, string memory playerName) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        require(stakeAmount > 0, "Invalid stake");
        require(bytes(playerName).length > 0, "Empty name");
        require(playerCurrentStake[msg.sender] == 0, "Already in queue");
        
        // Transfer USDC from player
        require(
            usdc.transferFrom(msg.sender, address(this), stakeAmount),
            "Transfer failed"
        );
        
        playerCurrentStake[msg.sender] = stakeAmount;
        
        // Find or create queue
        uint256 queueIndex = _findOrCreateQueue(stakeAmount);
        MatchQueue storage queue = queues[stakeAmount][queueIndex];
        
        // Add player to queue
        queue.players.push(msg.sender);
        queue.playerNames.push(playerName);
        queue.hasJoined[msg.sender] = true;
        
        emit PlayerJoinedQueue(
            msg.sender,
            playerName,
            stakeAmount,
            queueIndex,
            queue.players.length
        );
        
        // Check if we can start a game
        if (queue.players.length >= MIN_PLAYERS && !queue.gameStarted) {
            _createGame(stakeAmount, queueIndex);
        }
    }
    
    /**
     * @notice Leave matchmaking queue and get refund
     */
    function leaveQueue() external nonReentrant {
        uint256 stake = playerCurrentStake[msg.sender];
        require(stake > 0, "Not in queue");
        
        // Find player in queue and remove
        MatchQueue[] storage stakeQueues = queues[stake];
        bool found = false;
        
        for (uint256 i = 0; i < stakeQueues.length; i++) {
            MatchQueue storage queue = stakeQueues[i];
            
            if (queue.hasJoined[msg.sender] && !queue.gameStarted) {
                // Remove player
                _removePlayerFromQueue(queue, msg.sender);
                found = true;
                break;
            }
        }
        
        require(found, "Not in active queue");
        
        // Refund
        delete playerCurrentStake[msg.sender];
        require(usdc.transfer(msg.sender, stake), "Refund failed");
        
        emit PlayerLeftQueue(msg.sender, stake, stake);
    }
    
    /**
     * @notice Create game when queue has enough players
     * @dev Internal function called when MIN_PLAYERS reached
     */
    function _createGame(uint256 stakeAmount, uint256 queueIndex) internal {
        MatchQueue storage queue = queues[stakeAmount][queueIndex];
        require(!queue.gameStarted, "Already started");
        require(queue.players.length >= MIN_PLAYERS, "Not enough players");
        
        queue.gameStarted = true;
        
        // Generate game session ID
        string memory gameSessionId = _generateGameSessionId(stakeAmount, queueIndex);
        queue.gameSessionId = gameSessionId;
        
        // Calculate prize pool and fees
        uint256 totalPool = stakeAmount * queue.players.length;
        uint256 platformFee = (totalPool * platformFeePercent) / 100;
        uint256 prizePool = totalPool - platformFee;
        
        // Create active game
        ActiveGame storage game = activeGames[gameSessionId];
        game.stakeAmount = stakeAmount;
        game.prizePool = prizePool;
        game.platformFee = platformFee;
        game.startedAt = block.timestamp;
        
        // Copy players (can't directly assign dynamic arrays)
        for (uint256 i = 0; i < queue.players.length; i++) {
            game.players.push(queue.players[i]);
            delete playerCurrentStake[queue.players[i]];
        }
        
        gameSessionExists[gameSessionId] = true;
        
        // Transfer platform fee to treasury
        require(usdc.transfer(platformTreasury, platformFee), "Fee transfer failed");
        
        emit GameMatched(
            gameSessionId,
            stakeAmount,
            queue.players,
            queue.playerNames,
            prizePool,
            platformFee
        );
    }
    
    /**
     * @notice Distribute prizes to winners (called by backend after game ends)
     * @param gameSessionId Unique game identifier
     * @param winners Array of winner addresses [1st, 2nd, 3rd]
     * @param signature Backend signature for verification
     */
    function distributePrizes(
        string memory gameSessionId,
        address[3] memory winners,
        bytes memory signature
    ) external nonReentrant whenNotPaused {
        ActiveGame storage game = activeGames[gameSessionId];
        
        require(gameSessionExists[gameSessionId], "Game doesn't exist");
        require(!game.completed, "Already completed");
        require(!game.paidOut, "Already paid out");
        
        // Verify all winners are valid players
        for (uint256 i = 0; i < 3; i++) {
            require(_isPlayer(game.players, winners[i]), "Invalid winner");
        }
        
        // Verify signature from backend
        bytes32 messageHash = keccak256(
            abi.encodePacked(gameSessionId, winners[0], winners[1], winners[2])
        );
        require(_verifySignature(messageHash, signature), "Invalid signature");
        
        // Calculate individual prizes
        uint256 firstPrize = (game.prizePool * FIRST_PLACE_BP) / 10000;
        uint256 secondPrize = (game.prizePool * SECOND_PLACE_BP) / 10000;
        uint256 thirdPrize = (game.prizePool * THIRD_PLACE_BP) / 10000;
        
        // Mark as completed before transfers (CEI pattern)
        game.completed = true;
        game.paidOut = true;
        game.completedAt = block.timestamp;
        totalGamesCompleted++;
        totalPrizesDistributed += game.prizePool;
        
        // Transfer prizes
        require(usdc.transfer(winners[0], firstPrize), "1st prize failed");
        require(usdc.transfer(winners[1], secondPrize), "2nd prize failed");
        require(usdc.transfer(winners[2], thirdPrize), "3rd prize failed");
        
        emit GameCompleted(
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
     * @notice Find existing open queue or create new one
     * @param stakeAmount Stake amount for the queue
     * @return Index of the queue
     */
    function _findOrCreateQueue(uint256 stakeAmount) internal returns (uint256) {
        MatchQueue[] storage stakeQueues = queues[stakeAmount];
        
        // Find open queue (not started, not full, not timed out)
        for (uint256 i = 0; i < stakeQueues.length; i++) {
            MatchQueue storage queue = stakeQueues[i];
            
            if (!queue.gameStarted && 
                queue.players.length < MAX_PLAYERS &&
                block.timestamp - queue.createdAt < QUEUE_TIMEOUT) {
                return i;
            }
        }
        
        // Create new queue
        stakeQueues.push();
        uint256 newIndex = stakeQueues.length - 1;
        stakeQueues[newIndex].stakeAmount = stakeAmount;
        stakeQueues[newIndex].createdAt = block.timestamp;
        
        return newIndex;
    }
    
    /**
     * @notice Remove player from queue
     */
    function _removePlayerFromQueue(MatchQueue storage queue, address player) internal {
        uint256 playerIndex = type(uint256).max;
        
        // Find player index
        for (uint256 i = 0; i < queue.players.length; i++) {
            if (queue.players[i] == player) {
                playerIndex = i;
                break;
            }
        }
        
        if (playerIndex != type(uint256).max) {
            // Swap with last and pop
            uint256 lastIndex = queue.players.length - 1;
            if (playerIndex != lastIndex) {
                queue.players[playerIndex] = queue.players[lastIndex];
                queue.playerNames[playerIndex] = queue.playerNames[lastIndex];
            }
            queue.players.pop();
            queue.playerNames.pop();
            delete queue.hasJoined[player];
        }
    }
    
    /**
     * @notice Check if address is a player in the game
     */
    function _isPlayer(address[] memory players, address check) internal pure returns (bool) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == check) return true;
        }
        return false;
    }
    
    /**
     * @notice Verify backend signature
     */
    function _verifySignature(bytes32 messageHash, bytes memory signature) 
        internal 
        view 
        returns (bool) 
    {
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address recovered = ethSignedMessageHash.recover(signature);
        return recovered == backendSigner;
    }
    
    /**
     * @notice Generate unique game session ID
     */
    function _generateGameSessionId(uint256 stakeAmount, uint256 queueIndex) 
        internal 
        view 
        returns (string memory) 
    {
        return string(abi.encodePacked(
            "CASH_",
            _uint2str(stakeAmount),
            "_",
            _uint2str(block.timestamp),
            "_",
            _uint2str(queueIndex)
        ));
    }
    
    /**
     * @notice Convert uint to string
     */
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
    
    /**
     * @notice Update backend signer (admin only)
     */
    function updateBackendSigner(address newSigner) external {
        require(msg.sender == factory, "Only factory");
        require(newSigner != address(0), "Invalid signer");
        
        address oldSigner = backendSigner;
        backendSigner = newSigner;
        
        emit BackendSignerUpdated(oldSigner, newSigner);
    }
    
    /**
     * @notice Get queue information
     */
    function getQueueInfo(uint256 stakeAmount, uint256 queueIndex) 
        external 
        view 
        returns (
            uint256 playerCount,
            bool started,
            uint256 createdAt,
            address[] memory players
        ) 
    {
        require(queueIndex < queues[stakeAmount].length, "Invalid index");
        MatchQueue storage queue = queues[stakeAmount][queueIndex];
        
        return (
            queue.players.length,
            queue.gameStarted,
            queue.createdAt,
            queue.players
        );
    }
    
    /**
     * @notice Get active game information
     */
    function getGameInfo(string memory gameSessionId) 
        external 
        view 
        returns (
            uint256 stakeAmount,
            address[] memory players,
            uint256 prizePool,
            bool completed,
            bool paidOut
        ) 
    {
        ActiveGame storage game = activeGames[gameSessionId];
        return (
            game.stakeAmount,
            game.players,
            game.prizePool,
            game.completed,
            game.paidOut
        );
    }
    
    /**
     * @notice Pause contract (only factory)
     */
    function pause() external {
        require(msg.sender == factory, "Only factory");
        _pause();
    }
    
    /**
     * @notice Unpause contract (only factory)
     */
    function unpause() external {
        require(msg.sender == factory, "Only factory");
        _unpause();
    }
}