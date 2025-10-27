// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GameFactory
 * @notice Central registry and admin contract for the quiz game platform
 * @dev Manages all game contracts, fees, and platform configuration
 */
contract GameFactory is AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant BACKEND_ROLE = keccak256("BACKEND_ROLE");
    
    // Platform configuration
    IERC20 public immutable usdc;
    address public platformTreasury;
    uint256 public platformFeePercent = 10; // 10% = 1000 basis points
    
    // Contract addresses
    address public cashGameContract;
    address public pointsRedemptionContract;
    address public sponsoredGamesContract;
    
    // Stats tracking
    uint256 public totalGamesCreated;
    uint256 public totalPrizesDistributed;
    uint256 public totalFeesCollected;
    
    // Events
    event ContractDeployed(string contractType, address contractAddress);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event EmergencyWithdraw(address token, uint256 amount, address to);
    
    constructor(address _usdc, address _treasury) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_treasury != address(0), "Invalid treasury");
        
        usdc = IERC20(_usdc);
        platformTreasury = _treasury;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @notice Register a deployed game contract
     * @param contractType Type of contract (cash, points, sponsored)
     * @param contractAddress Address of the deployed contract
     */
    function registerContract(string memory contractType, address contractAddress) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(contractAddress != address(0), "Invalid address");
        
        bytes32 typeHash = keccak256(abi.encodePacked(contractType));
        
        if (typeHash == keccak256("cash")) {
            cashGameContract = contractAddress;
        } else if (typeHash == keccak256("points")) {
            pointsRedemptionContract = contractAddress;
        } else if (typeHash == keccak256("sponsored")) {
            sponsoredGamesContract = contractAddress;
        } else {
            revert("Unknown contract type");
        }
        
        emit ContractDeployed(contractType, contractAddress);
    }
    
    /**
     * @notice Update platform fee percentage
     * @param newFeePercent New fee percentage (e.g., 10 for 10%)
     */
    function updatePlatformFee(uint256 newFeePercent) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(newFeePercent <= 20, "Fee too high"); // Max 20%
        
        uint256 oldFee = platformFeePercent;
        platformFeePercent = newFeePercent;
        
        emit PlatformFeeUpdated(oldFee, newFeePercent);
    }
    
    /**
     * @notice Update platform treasury address
     * @param newTreasury New treasury address
     */
    function updateTreasury(address newTreasury) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(newTreasury != address(0), "Invalid treasury");
        
        address oldTreasury = platformTreasury;
        platformTreasury = newTreasury;
        
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
    
    /**
     * @notice Grant backend role to an address
     * @param backend Address to grant backend role
     */
    function addBackendSigner(address backend) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        grantRole(BACKEND_ROLE, backend);
    }
    
    /**
     * @notice Revoke backend role from an address
     * @param backend Address to revoke backend role
     */
    function removeBackendSigner(address backend) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        revokeRole(BACKEND_ROLE, backend);
    }
    
    /**
     * @notice Pause all platform operations
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpause platform operations
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @notice Emergency withdraw (only for stuck funds)
     * @param token Token address (use address(0) for ETH)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (token == address(0)) {
            payable(platformTreasury).transfer(amount);
        } else {
            IERC20(token).transfer(platformTreasury, amount);
        }
        
        emit EmergencyWithdraw(token, amount, platformTreasury);
    }
    
    /**
     * @notice Get all registered contract addresses
     */
    function getContracts() 
        external 
        view 
        returns (address cash, address points, address sponsored) 
    {
        return (cashGameContract, pointsRedemptionContract, sponsoredGamesContract);
    }
}