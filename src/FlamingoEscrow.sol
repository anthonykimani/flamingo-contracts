// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FlamingoEscrow is ReentrancyGuard {
    IERC20 public immutable USDC;
    address public immutable PLATFORM_TREASURY;
    address public backendSigner;
    uint256 public constant PLATFORM_FEE_PERCENT = 10;
    
    // Prize Distribution
    uint256 public constant FIRST_PLACE_BP = 5000;
    uint256 public constant SECOND_PLACE_BP = 3000;
    uint256 public constant THIRD_PLACE_BP = 2000;

    // Game State
    struct GameSession {
        uint256 prizePool;
        uint256 platformFee;
        address[] players;
        bool paidOut;
        uint256 createdAt;
        uint256 paidOutAt;
    }

    mapping(string => GameSession) public games;
    mapping(string => bool) public gameExists;

    mapping(string => mapping(address => uint256)) public playerDeposits;

    // Events
    event PlayerDeposited (
        string indexed gameSessionId,
        address indexed player,
        uint256 amount
    );

    event GameSessionCreated (
        string indexed gameSessionId,
        uint256 totalPrizePool,
        uint256 platformFee,
        address[] players
    );

    event PrizeDistributed (
        string indexed gameSessionId,
        address indexed firstPlace,
        address indexed secondPlace,
        address indexed thirdPlace,
        uint256 firstPrize,
        uint256 secondPrize,
        uint256 thirdPrize
    );

    constructor (
        address _usdc,
        address _treasury,
        address _backedSigner
    ) {
        require(_usdc != address(0), "Invalid USDC");
        require(_treasury != address(0), "Invalid Treasury");
        require(_backedSigner != address(0), "Invalid Signer");

        USDC = IERC20(_usdc);
        PLATFORM_TREASURY = _treasury;
        backendSigner = _backedSigner;
    }

    function deposit(string calldata gameSessionId, uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(playerDeposits[gameSessionId][msg.sender] == 0, "Already Deposited");

        require(transferFrom(msg.sender, address(this), amount), "Transfer Failed");

        playerDeposits[gameSessionId][msg.sender] = amount;

        emit PlayerDeposited(
            gameSessionId,
            msg.sender,
            amount
        );
    }
}