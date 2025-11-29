// script/DeployFlamingoEscrow.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {FlamingoEscrow} from "../src/FlamingoEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployFlamingoEscrow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("PLATFORM_TREASURY");
        address backendSigner = vm.envAddress("BACKEND_SIGNER");
        
        address usdcAddress = getUSDCAddress(); // for USDC 
        address cUSDAddress = getCUSDAddress(); // for cUSD
        
        console2.log("\n=== Deployment Configuration ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("Deployer:", vm.addr(deployerPrivateKey));
        console2.log("cUSD:", cUSDAddress);
        console2.log("Treasury:", treasury);
        console2.log("Backend Signer:", backendSigner);
        
        vm.startBroadcast(deployerPrivateKey);
        
        if (cUSDAddress == address(0)) {
            console2.log("\nDeploying Mock USDC...");
            MockUSDC mockUSDC = new MockUSDC();
            cUSDAddress = address(mockUSDC);
            console2.log("Mock USDC deployed at:", cUSDAddress);
            
            mockUSDC.mint(vm.addr(deployerPrivateKey), 1_000_000 * 1e6);
            console2.log("Minted 1M USDC to deployer");
        }
        
        console2.log("\n=== Deploying FlamingoEscrow ===");
        FlamingoEscrow escrow = new FlamingoEscrow(
            cUSDAddress,
            treasury,
            backendSigner
        );
        
        console2.log("\n=== Deployment Successful ===");
        console2.log("FlamingoEscrow:", address(escrow));
        console2.log("Block:", block.number);
        
        console2.log("\n=== Verifying Configuration ===");
        require(address(escrow.USDC()) == cUSDAddress, "USDC mismatch");
        require(escrow.PLATFORM_TREASURY() == treasury, "Treasury mismatch");
        require(escrow.backendSigner() == backendSigner, "Signer mismatch");
        require(escrow.owner() == vm.addr(deployerPrivateKey), "Owner mismatch");
        
        console2.log("Platform Fee:", escrow.PLATFORM_FEE_PERCENT(), "%");
        console2.log("First Place:", escrow.FIRST_PLACE_BP() / 100, "%");
        console2.log("Second Place:", escrow.SECOND_PLACE_BP() / 100, "%");
        console2.log("Third Place:", escrow.THIRD_PLACE_BP() / 100, "%");
        
        vm.stopBroadcast();
        
        // Print deployment info
        printDeploymentInfo(address(escrow), cUSDAddress);
    }
    
    function printDeploymentInfo(address escrow, address usdc) internal view {
        console2.log("\n");
        console2.log("DEPLOYMENT COMPLETE - SAVE THIS INFO");
        console2.log("Network: Celo Sepolia");
        console2.log("Chain ID:", block.chainid);
        console2.log("");
        console2.log("FlamingoEscrow:", escrow);
        console2.log("USDC:", usdc);
        console2.log("");
        console2.log("Explorer:");
        console2.log("https://celo-sepolia.blockscout.com//address/", escrow);
        console2.log("");
        console2.log("UPDATE YOUR BACKEND .env WITH:");
        console2.log("");
        console2.log("ESCROW_CONTRACT_ADDRESS=", escrow);
        console2.log("USDC_ADDRESS=", usdc);
        console2.log("RPC_URL=https://forno.celo-sepolia.celo-testnet.org");
        console2.log("");
    }
    
    function getUSDCAddress() internal view returns (address) {
        uint256 chainId = block.chainid;
        
        if (chainId == 84532) return 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia
        if (chainId == 8453) return 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;  // Base
        if (chainId == 11142220) return 0x01C5C0122039549AD1493B8220cABEdD739BC44E ; // Celo Sepolia
        if (chainId == 11155111) return 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Sepolia
        if (chainId == 421614) return 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;  // Arbitrum Sepolia
        if (chainId == 1) return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;      // Mainnet
        
        return address(0);
    }

    function getCUSDAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        if (chainId == 11142220) return 0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b; // CUSD Sepolia

        return address(0);
    }
}

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}