// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FlamingoTokenWithExtensions
 * @notice Token with vesting, airdrop, and allocation management
 */
contract FlamingoTokenWithExtensions is ERC20, Ownable, ReentrancyGuard {
    uint256 public constant TOTAL_SUPPLY = 100_000_000_000 * 10**18;
    
    // Allocations (matching Drawcast)
    uint256 public constant COMMUNITY_ALLOCATION = 30_000_000_000 * 10**18; // 30%
    uint256 public constant TEAM_ALLOCATION = 20_000_000_000 * 10**18; // 20%
    uint256 public constant PROJECT_ALLOCATION = 30_000_000_000 * 10**18; // 30%
    uint256 public constant LIQUIDITY_ALLOCATION = 20_000_000_000 * 10**18; // 20%
    
    // Vesting configuration
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 released;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 vestingDuration;
    }
    
    mapping(address => VestingSchedule) public vestingSchedules;
    
    // Airdrop tracking
    mapping(address => uint256) public airdropAllocations;
    mapping(address => bool) public airdropClaimed;
    
    // Metadata
    string private _description;
    string private _telegram;
    string private _website;
    string private _twitter;
    string private _farcaster;
    
    // Events
    event VestingCreated(address indexed beneficiary, uint256 amount, uint256 cliffDuration, uint256 vestingDuration);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event AirdropAllocated(address indexed user, uint256 amount);
    event AirdropClaimed(address indexed user, uint256 amount);
    
    constructor(
        string memory name,
        string memory symbol,
        string memory description,
        string memory telegram,
        string memory website,
        string memory twitter,
        string memory farcaster
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _description = description;
        _telegram = telegram;
        _website = website;
        _twitter = twitter;
        _farcaster = farcaster;
        
        // Mint entire supply to contract
        // Owner will distribute according to tokenomics
        _mint(address(this), TOTAL_SUPPLY);
    }
    
    /**
     * @notice Create vesting schedule for an address
     */
    function createVesting(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 vestingDuration
    ) external onlyOwner {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Amount must be > 0");
        require(vestingSchedules[beneficiary].totalAmount == 0, "Vesting already exists");
        
        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            released: 0,
            startTime: block.timestamp,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration
        });
        
        emit VestingCreated(beneficiary, amount, cliffDuration, vestingDuration);
    }
    
    /**
     * @notice Release vested tokens
     */
    function release() external nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.totalAmount > 0, "No vesting schedule");
        
        uint256 releasable = _releasableAmount(schedule);
        require(releasable > 0, "No tokens to release");
        
        schedule.released += releasable;
        _transfer(address(this), msg.sender, releasable);
        
        emit TokensReleased(msg.sender, releasable);
    }
    
    /**
     * @notice Calculate releasable amount
     */
    function releasableAmount(address beneficiary) external view returns (uint256) {
        return _releasableAmount(vestingSchedules[beneficiary]);
    }
    
    function _releasableAmount(VestingSchedule memory schedule) private view returns (uint256) {
        if (block.timestamp < schedule.startTime + schedule.cliffDuration) {
            return 0;
        }
        
        uint256 elapsedTime = block.timestamp - schedule.startTime;
        uint256 vestedAmount;
        
        if (elapsedTime >= schedule.cliffDuration + schedule.vestingDuration) {
            vestedAmount = schedule.totalAmount;
        } else {
            uint256 vestingTime = elapsedTime - schedule.cliffDuration;
            vestedAmount = (schedule.totalAmount * vestingTime) / schedule.vestingDuration;
        }
        
        return vestedAmount - schedule.released;
    }
    
    /**
     * @notice Set airdrop allocations
     */
    function setAirdropAllocations(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(recipients.length == amounts.length, "Length mismatch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            airdropAllocations[recipients[i]] = amounts[i];
            emit AirdropAllocated(recipients[i], amounts[i]);
        }
    }
    
    /**
     * @notice Claim airdrop
     */
    function claimAirdrop() external nonReentrant {
        require(airdropAllocations[msg.sender] > 0, "No allocation");
        require(!airdropClaimed[msg.sender], "Already claimed");
        
        uint256 amount = airdropAllocations[msg.sender];
        airdropClaimed[msg.sender] = true;
        
        _transfer(address(this), msg.sender, amount);
        
        emit AirdropClaimed(msg.sender, amount);
    }
    
    /**
     * @notice Distribute tokens to allocation wallets
     */
    function distributeAllocations(
        address communityWallet,
        address projectWallet,
        address liquidityWallet
    ) external onlyOwner {
        require(communityWallet != address(0), "Invalid community wallet");
        require(projectWallet != address(0), "Invalid project wallet");
        require(liquidityWallet != address(0), "Invalid liquidity wallet");
        
        _transfer(address(this), communityWallet, COMMUNITY_ALLOCATION);
        _transfer(address(this), projectWallet, PROJECT_ALLOCATION);
        _transfer(address(this), liquidityWallet, LIQUIDITY_ALLOCATION);
        
        // Team allocation stays in contract for vesting
    }
    
    /**
     * @notice Burn tokens
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    // Metadata getters
    function description() external view returns (string memory) { return _description; }
    function telegram() external view returns (string memory) { return _telegram; }
    function website() external view returns (string memory) { return _website; }
    function twitter() external view returns (string memory) { return _twitter; }
    function farcaster() external view returns (string memory) { return _farcaster; }
}