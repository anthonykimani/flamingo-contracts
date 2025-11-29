# FlamingoEscrow Smart Contract

A secure, gas-optimized escrow system for quiz game deposits and automated prize distribution on EVM-compatible blockchains.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Contract Details](#contract-details)
- [Installation](#installation)
- [Usage](#usage)
- [Testing](#testing)
- [Security](#security)
- [Gas Optimization](#gas-optimization)
- [Deployment](#deployment)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Backend Integration](#backend-integration)
- [License](#license)

## 🎯 Overview

FlamingoEscrow is a battle-tested smart contract designed for managing deposits and prize distribution in competitive quiz games. It provides:

- **Secure Fund Management**: Players deposit USDC before games, funds are held in escrow
- **Automated Distribution**: Backend-verified winners receive prizes automatically
- **Fair Prize Split**: 50% / 30% / 20% distribution for 1st, 2nd, and 3rd place
- **Platform Fee**: 10% platform fee deducted from total prize pool
- **Player Protection**: Refund mechanisms for cancelled games or unmatched players

## ✨ Features

### Core Functionality
- ✅ **Player Deposits**: Secure USDC deposits with duplicate prevention
- ✅ **Game Session Creation**: Backend-controlled game initialization
- ✅ **Prize Distribution**: Automated payouts to top 3 winners
- ✅ **Refund System**: Pre-game and post-cancellation refunds
- ✅ **Emergency Functions**: Owner-controlled emergency withdrawal

### Security Features
- 🔐 **Signature Verification**: Backend-signed winner verification
- 🔐 **Replay Protection**: Domain separation with chain ID and contract address
- 🔐 **Signature Malleability Protection**: EIP-2 s-value validation
- 🔐 **Reentrancy Protection**: OpenZeppelin ReentrancyGuard
- 🔐 **Access Control**: Role-based permissions (Owner, Backend Signer)

### Gas Optimizations
- ⚡ **O(1) Player Lookup**: Mapping-based player verification
- ⚡ **bytes32 Game IDs**: Gas-efficient game identifiers
- ⚡ **Batch Operations**: Efficient multi-player processing
- ⚡ **SafeERC20**: Handles non-standard token implementations

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Frontend                              │
│  (Next.js + Reown AppKit + Smart Accounts)                  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                        Backend                               │
│  - Matchmaking logic                                         │
│  - Game state management                                     │
│  - Winner verification & signing                             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   FlamingoEscrow Contract                    │
│                                                              │
│  ┌────────────────┐  ┌────────────────┐  ┌───────────────┐ │
│  │ Player Deposits│  │  Game Sessions │  │Prize Payouts  │ │
│  │   (Pending)    │──│   (Active)     │──│  (Winners)    │ │
│  └────────────────┘  └────────────────┘  └───────────────┘ │
│                                                              │
│  Security: Signatures, Replay Protection, Reentrancy Guard  │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                        USDC Token                            │
└─────────────────────────────────────────────────────────────┘
```

## 📜 Contract Details

### State Variables

#### Immutable
- `USDC`: ERC20 token contract (typically USDC)
- `PLATFORM_TREASURY`: Receives platform fees
- `PLATFORM_FEE_PERCENT`: 10% fee on total deposits

#### Prize Distribution (Basis Points)
- `FIRST_PLACE_BP`: 5000 (50%)
- `SECOND_PLACE_BP`: 3000 (30%)
- `THIRD_PLACE_BP`: 2000 (20%)

#### Mutable
- `backendSigner`: Address authorized to create games and verify winners
- `games`: Mapping of game sessions
- `gameExists`: Quick game existence check
- `pendingDeposits`: Player deposits before game creation

### Key Functions

#### Player Functions
```solidity
function deposit(bytes32 gameSessionId, uint256 amount) external nonReentrant
function refundDeposit(bytes32 gameSessionId) external nonReentrant
```

#### Backend Functions
```solidity
function createGameSession(bytes32 gameSessionId, address[] calldata players) external
function distributePrizes(bytes32 gameSessionId, address[3] calldata winners, bytes calldata signature) external
function cancelGameSession(bytes32 gameSessionId) external
```

#### Admin Functions
```solidity
function updateBackendSigner(address newSigner) external onlyOwner
function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner
function emergencyWithdrawEth(address payable to, uint256 amount) external onlyOwner
```

#### View Functions
```solidity
function getGameInfo(bytes32 gameSessionId) external view returns (...)
function getPendingDeposit(bytes32 gameSessionId, address player) external view returns (uint256)
function getPlayerDeposit(bytes32 gameSessionId, address player) external view returns (uint256)
function isPlayerInGame(bytes32 gameSessionId, address player) external view returns (bool)
```

## 🚀 Installation

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation  ) installed (v1.4.4+)
- Node.js 16+ (for backend integration)
- Git

### Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd flamingo-contracts

# Install Foundry dependencies
forge install OpenZeppelin/openzeppelin-contracts

# Build the contracts
forge build

# Run tests
forge test

# Run tests with gas reporting
forge test --gas-report
```

## 🛠️ Build & Compile Commands

### Compilation
```bash
# Build all contracts
forge build

# Build with specific optimization
forge build --optimize --optimizer-runs 200

# Clean build artifacts
forge clean && forge build

# Check compilation without building
forge build --dry-run
```

### Testing & Validation
```bash
# Run full test suite
forge test

# Run specific test
forge test --match-test testDistributePrizes

# Run with gas report
forge test --gas-report

# Run with detailed traces
forge test -vvv

# Check contract sizes
forge build --sizes

# Generate coverage report
forge coverage
```

## 🎯 Deployment Commands

### Recommended: Solidity Script (Most Reliable)
```bash
# Deploy with Solidity script (handles verification automatically)
forge script script/DeployFlamingoEscrow.s.sol \
  --tc DeployFlamingoEscrow \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --chain base-sepolia

# Deploy to mainnet (use Ledger hardware wallet)
forge script script/DeployFlamingoEscrow.s.sol \
  --tc DeployFlamingoEscrow \
  --rpc-url $MAINNET_RPC_URL \
  --ledger \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --chain base
```

### Alternative: Direct Contract Creation
```bash
# Deploy contract only (skip verification)
forge create src/FlamingoEscrow.sol:FlamingoEscrow \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY \
  --constructor-args "0xUSDC_ADDRESS" "0xTREASURY_ADDRESS" "0xBACKEND_SIGNER" \
  --broadcast

# Then verify separately (see Verification section)
```

### Environment Setup
Create a `.env` file in your project root:
```bash
# Required for deployment
PRIVATE_KEY=0x...
ETHERSCAN_API_KEY=8VH51ZYHTX5D29XSPMQGE2ASU38IDQ2KWB

# Contract Configuration (optional, for scripts)
USDC_ADDRESS=0x036CbD53842c5426634e7929541eC2318f3dCF7e
TREASURY_ADDRESS=0x4A8E770a33631Bb909c424CaA8C48BbC28Be96b1
BACKEND_SIGNER=0x4A8E770a33631Bb909c424CaA8C48BbC28Be96b1
```

**⚠️ Security Note**: Never commit `.env` files. Add to `.gitignore`.

## 💻 Usage

### Game Flow

#### 1. Player Deposits
```solidity
// Player approves USDC spending
USDC.approve(escrowAddress, depositAmount);

// Player deposits for a game
escrow.deposit(gameSessionId, depositAmount);
```

#### 2. Backend Creates Game
```solidity
// After matching 3+ players
address[] memory players = [player1, player2, player3];
escrow.createGameSession(gameSessionId, players);
```

#### 3. Game Completes & Winners Determined
```solidity
// Backend signs the winners
address[3] memory winners = [winner1, winner2, winner3];
bytes memory signature = signWinners(gameSessionId, winners);

// Anyone can trigger distribution with valid signature
escrow.distributePrizes(gameSessionId, winners, signature);
```

#### 4. Refund Scenarios

**Before Game Creation:**
```solidity
// Player can refund if game hasn't started
escrow.refundDeposit(gameSessionId);
```

**After Cancellation:**
```solidity
// Backend cancels game
escrow.cancelGameSession(gameSessionId);

// Players can now refund
escrow.refundDeposit(gameSessionId);
```

## 🧪 Testing

### Test Coverage

The test suite includes **25 comprehensive tests** covering:

#### Basic Functionality (7 tests)
- ✅ Player deposits
- ✅ Game session creation
- ✅ Prize distribution
- ✅ Game cancellation
- ✅ Refunds (before & after cancellation)
- ✅ Emergency withdrawals
- ✅ Backend signer updates

#### Security Tests (11 tests)
- ✅ Duplicate deposit prevention
- ✅ Double payout prevention
- ✅ Duplicate winner prevention
- ✅ Non-player winner rejection
- ✅ Signature replay protection
- ✅ Invalid signature rejection
- ✅ Access control (owner, backend)
- ✅ Refund restrictions

#### Edge Cases & Gas Tests (7 tests)
- ✅ Dust handling (rounding)
- ✅ Multiple independent games
- ✅ Helper function validation
- ✅ O(1) player lookup verification
- ✅ Gas benchmarking

### Running Tests

```bash
# Run all tests
forge test

# Run specific test
forge test --match-test testDistributePrizes

# Run with verbose output
forge test -vvv

# Run with gas report
forge test --gas-report

# Run with coverage
forge coverage
```

### Test Results
```
Running 25 tests for test/FlamingoEscrow.t.sol:FlamingoEscrowTest
[PASS] testCancelGameSession() (gas: 502058)
[PASS] testCannotCancelAfterPayout() (gas: 559689)
[PASS] testCannotDepositTwice() (gas: 86264)
[PASS] testCannotDistributeToNonPlayer() (gas: 488415)
[PASS] testCannotDistributeTwice() (gas: 559725)
[PASS] testCannotDistributeWithDuplicateWinners() (gas: 482398)
[PASS] testCannotRefundAfterGameStartedWithoutCancel() (gas: 474642)
[PASS] testCreateGameSession() (gas: 481946)
[PASS] testDeposit() (gas: 89655)
[PASS] testDistributePrizes() (gas: 567069)
[PASS] testDustHandling() (gas: 565417)
[PASS] testEmergencyWithdraw() (gas: 103928)
[PASS] testGasDeposit() (gas: 84074)
[PASS] testGasDistribute() (gas: 559729)
[PASS] testHelperFunctions() (gas: 7575)
[PASS] testInvalidSignature() (gas: 492079)
[PASS] testIsPlayerLookup() (gas: 472455)
[PASS] testMultipleGamesIndependent() (gas: 120137)
[PASS] testOnlyBackendCanCancelGame() (gas: 469184)
[PASS] testOnlyBackendCanCreateGame() (gas: 177092)
[PASS] testOnlyOwnerCanUpdateSigner() (gas: 16165)
[PASS] testRefundAfterCancellation() (gas: 488424)
[PASS] testRefundBeforeGameCreation() (gas: 77040)
[PASS] testSignatureReplayProtection() (gas: 999755)
[PASS] testUpdateBackendSigner() (gas: 28237)

Suite result: ok. 25 passed; 0 failed; 0 skipped
```

## 🔒 Security

### Audit Checklist

- ✅ **Reentrancy Protection**: ReentrancyGuard on all state-changing functions
- ✅ **Access Control**: Ownable + backend signer role
- ✅ **Input Validation**: All user inputs validated
- ✅ **CEI Pattern**: Checks-Effects-Interactions pattern followed
- ✅ **SafeERC20**: Handles non-standard tokens
- ✅ **Signature Verification**: Multiple layers of validation
- ✅ **Replay Protection**: Domain separation + chain ID
- ✅ **Malleability Protection**: EIP-2 s-value check
- ✅ **Integer Overflow**: Solidity 0.8+ built-in protection
- ✅ **Emergency Functions**: Owner can rescue stuck funds

### Known Considerations

1. **Backend Dependency**: Contract relies on backend for matchmaking and winner verification
2. **Single Backend Signer**: Only one backend signer allowed (can be updated by owner)
3. **Platform Fee**: Fixed 10% fee (not configurable post-deployment)
4. **Minimum Players**: Games require minimum 3 players

## ⚡ Gas Optimization

### Benchmarks

| Operation               | Gas Cost | Notes                  |
| ----------------------- | -------- | ---------------------- |
| Deposit                 | ~84,000  | First deposit for game |
| Create Game (3 players) | ~482,000 | Includes fee transfer  |
| Distribute Prizes       | ~560,000 | 3 winner payouts       |
| Refund                  | ~77,000  | Before game creation   |
| Player Lookup           | <5,000   | O(1) mapping lookup    |

### Optimization Techniques

1. **bytes32 Game IDs**: More gas-efficient than strings
2. **Mapping Lookups**: O(1) player verification
3. **Batch Processing**: Process multiple players in one transaction
4. **Storage Packing**: Efficient struct layout
5. **SafeERC20**: Only for necessary safety checks

## ✅ Verification

### Automated Verification (Recommended)

When using `forge script` with `--verify` flag, verification is automatic. For manual verification:

```bash
# Create constructor arguments file (192 hex characters, no 0x, no newline)
# Format: USDC_ADDRESS (32 bytes) + TREASURY_ADDRESS (32 bytes) + BACKEND_SIGNER (32 bytes)
printf "%s" "000000000000000000000000036cbd53842c5426634e7929541ec2318f3dcf7e0000000000000000000000004a8e770a33631bb909c424caa8c48bbc28be96b10000000000000000000000004a8e770a33631bb909c424caa8c48bbc28be96b1" > args.txt

# Verify contract
forge verify-contract DEPLOYED_CONTRACT_ADDRESS \
  src/FlamingoEscrow.sol:FlamingoEscrow \
  --chain base-sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --constructor-args-path args.txt \
  --num-of-optimizations 200 \
  --watch
```

### API Key Requirements

**⚠️ IMPORTANT**: Basescan now requires **Etherscan API V2** (Universal API Key):
- Get your key from https://etherscan.io/myapikey
- Legacy Basescan keys are deprecated
- Format: `8VH51ZYHTX5D29XSPMQGE2ASU38IDQ2KWB`

### Manual Verification

If automated verification fails, use the form at:
`https://sepolia.basescan.org/verifyContract`

**Required Parameters:**
- **Compiler**: Solidity v0.8.20+commit.a1b79de6
- **Optimization**: Yes, 200 runs
- **Constructor Arguments**: Concatenated ABI-encoded addresses (192 hex chars)
- **License**: MIT

## 🔧 Troubleshooting

### Common Issues & Solutions

| Error                                 | Cause                                            | Solution                                        |
| ------------------------------------- | ------------------------------------------------ | ----------------------------------------------- |
| `add --broadcast to previous command` | `--broadcast` not recognized in complex commands | Use **forge script** approach instead           |
| `Multiple contracts in target path`   | Script has multiple contracts                    | Add `--tc ContractName` flag                    |
| `Member "repeat" not found`           | Used JavaScript `.repeat()` in Solidity          | Use plain strings or loops in Solidity          |
| `Could not detect deployment`         | No RPC URL or wrong network                      | Verify RPC URL and chain ID                     |
| `invalid string length`               | Constructor args have 0x prefix or newline       | Use `printf "%s" "hexstring" > args.txt`        |
| `unexpected argument`                 | Shell parsing error                              | Pass args as single hex string or use file      |
| `NOTOK - deprecated V1 endpoint`      | Old Basescan API key                             | **Use Etherscan Universal API Key**             |
| `Invalid API Key`                     | Wrong key format                                 | Key must be from etherscan.io, not basescan.org |

### Constructor Arguments Format

**Correct:** 192 hex characters, no 0x prefix, no newline
```
000000000000000000000000036cbd53842c5426634e7929541ec2318f3dcf7e0000000000000000000000004a8e770a33631bb909c424caa8c48bbc28be96b10000000000000000000000004a8e770a33631bb909c424caa8c48bbc28be96b1
```

**Wrong:**
```
0x0000... (with 0x prefix)
0000\n (with newline)
0x000...\n (both)
```

### Getting Contract Address from Transaction

```bash
# If you lost your contract address
cast receipt $DEPLOY_TX_HASH \
  --rpc-url https://sepolia.base.org \
  --field contractAddress
```

## 📦 Live Deployments

### Celo Sepolia (Chain ID: 11142220)

**Contract Address**: `0x482D7c8626cf7BeEA5299179aaB5c22c8aBA93E1`  
**Block**: 34136618  
**Deployer**: `0xfA1316fE4b4a572F5F701f75A97bae933a24B748`  
**Status**: ✅ Verified  
**Explorer**: `https://celo-sepolia.blockscout.com/tx/0xafc69c8a8dad93066407697caf7a9ab5da7be746f652bbd5e672eefcc2778eda`

**Deployment Transaction**: `0xafc69c8a8dad93066407697caf7a9ab5da7be746f652bbd5e672eefcc2778eda`

### Base Sepolia (Chain ID: 84532)

**Contract Address**: `0x8a0E220d6f5250D2aA3273a634387546e671573D`  
**Block**: 34136618  
**Deployer**: `0x4A8E770a33631Bb909c424CaA8C48BbC28Be96b1`  
**Status**: ✅ Verified  
**Explorer**: https://sepolia.basescan.org/address/0x8a0e220d6f5250d2aa3273a634387546e671573d#code

**Deployment Transaction**: `0x08135f3199f76645f0f0227ad51c13c13ae6ccb95966a7ccd99ca781c98c0c3b`

**Successful Deployment Command Used:**
```bash
forge script script/DeployFlamingoEscrow.s.sol \
 --tc DeployFlamingoEscrow  \ 
 --rpc-url https://forno.celo-sepolia.celo-testnet.org  \ 
 --private-key "$PRIVATE_KEY" \  
 --broadcast \  
 --verify  \ 
 --etherscan-api-key "$ETHERSCAN_API_KEY" \  
 --chain celo-sepolia
```


**Configuration:**
- Platform Fee: 10%
- First Place: 50%
- Second Place: 30%
- Third Place: 20%
- USDC: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
- Treasury: `0x4A8E770a33631Bb909c424CaA8C48BbC28Be96b1`
- Backend Signer: `0x4A8E770a33631Bb909c424CaA8C48BbC28Be96b1`

**Successful Deployment Command Used:**
```bash
forge script script/DeployFlamingoEscrow.s.sol \
  --tc DeployFlamingoEscrow \
  --rpc-url https://sepolia.base.org \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --chain base-sepolia
```


# 🎉 SUCCESS! Base Mainnet (Chain ID: 8453)

## ✅ Deployment Summary

**🚀 Contract Address**: `0x482D7c8626cf7BeEA5299179aaB5c22c8aBA93E1`  
**🔍 Verified on Basescan**: https://basescan.org/address/0x482d7c8626cf7beea5299179aab5c22c8aba93e1  
**📦 Block**: 38631385  
**⛽ Gas Used**: 3,821,097 gas  
**💰 Cost**: 0.000004344 ETH (~$0.013)

## 📋 Contract Configuration
- **Chain**: Base Mainnet (Chain ID: 8453)
- **USDC**: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- **Platform Treasury**: `0xfA1316fE4b4a572F5F701f75A97bae933a24B748`
- **Backend Signer**: `0xfA1316fE4b4a572F5F701f75A97bae933a24B748`
- **Platform Fee**: 10%
- **Prize Split**: 50%/30%/20%

---

**Deployment Command:**
```bash
forge script script/DeployFlamingoEscrow.s.sol \
  --tc DeployFlamingoEscrow \
  --rpc-url https://mainnet.base.org \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --chain base
```

## 📊 Production Configuration

Update your backend `.env`:


## 🔗 Backend Integration

### Node.js Example

```javascript
const { ethers } = require('ethers');

// Initialize
const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
const backendWallet = new ethers.Wallet(BACKEND_PRIVATE_KEY, provider);
const escrow = new ethers.Contract(ESCROW_ADDRESS, ESCROW_ABI, backendWallet);

// Create game session
async function createGameSession(gameId, players) {
    const tx = await escrow.createGameSession(
        ethers.utils.formatBytes32String(gameId),
        players
    );
    await tx.wait();
    console.log('Game created:', tx.hash);
}

// Sign winners
async function signWinners(gameId, winners) {
    const messageHash = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(
            ['address', 'uint256', 'bytes32', 'address', 'address', 'address'],
            [
                escrow.address,
                await provider.getNetwork().then(n => n.chainId),
                ethers.utils.formatBytes32String(gameId),
                winners[0],
                winners[1],
                winners[2]
            ]
        )
    );
    
    const ethSignedMessageHash = ethers.utils.keccak256(
        ethers.utils.solidityPack(
            ['string', 'bytes32'],
            ['\x19Ethereum Signed Message:\n32', messageHash]
        )
    );
    
    const signature = await backendWallet.signMessage(
        ethers.utils.arrayify(ethSignedMessageHash)
    );
    
    return signature;
}

// Distribute prizes
async function distributePrizes(gameId, winners) {
    const signature = await signWinners(gameId, winners);
    const tx = await escrow.distributePrizes(
        ethers.utils.formatBytes32String(gameId),
        winners,
        signature
    );
    await tx.wait();
    console.log('Prizes distributed:', tx.hash);
}

// Cancel game
async function cancelGame(gameId) {
    const tx = await escrow.cancelGameSession(
        ethers.utils.formatBytes32String(gameId)
    );
    await tx.wait();
    console.log('Game cancelled:', tx.hash);
}
```

### Frontend Integration (React + Reown AppKit)

```javascript
import { useAppKitAccount } from '@reown/appkit/react';
import { useWriteContract } from 'wagmi';

function DepositButton({ gameId, amount }) {
    const { address, isConnected } = useAppKitAccount();
    const { writeContract } = useWriteContract();

    const handleDeposit = async () => {
        if (!isConnected) return;
        
        // First approve USDC
        await writeContract({
            address: USDC_ADDRESS,
            abi: USDC_ABI,
            functionName: 'approve',
            args: [ESCROW_ADDRESS, amount]
        });
        
        // Then deposit
        await writeContract({
            address: ESCROW_ADDRESS,
            abi: ESCROW_ABI,
            functionName: 'deposit',
            args: [gameId, amount]
        });
    };

    return (
        <button onClick={handleDeposit} disabled={!isConnected}>
            Deposit {ethers.utils.formatUnits(amount, 6)} USDC
        </button>
    );
}
```

## 📊 Events

The contract emits the following events for off-chain tracking:

```solidity
event PlayerDeposited(bytes32 indexed gameSessionId, address indexed player, uint256 amount);
event GameSessionCreated(bytes32 indexed gameSessionId, uint256 totalPrizePool, uint256 platformFee, address[] players);
event PrizesDistributed(bytes32 indexed gameSessionId, address indexed firstPlace, address indexed secondPlace, address thirdPlace, uint256 firstPrize, uint256 secondPrize, uint256 thirdPrize);
event DepositRefunded(bytes32 indexed gameSessionId, address indexed player, uint256 amount);
event GameSessionCancelled(bytes32 indexed gameSessionId, uint256 timestamp);
event BackendSignerUpdated(address indexed oldSigner, address indexed newSigner);
event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);
```

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for new functionality
4. Ensure all tests pass (`forge test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- Documentation: [Link to docs]
- Discord: [Link to Discord]
- Email: support@flamingo.app

## 🔮 Future Enhancements

- [ ] Multi-token support (not just USDC)
- [ ] Configurable prize distribution
- [ ] Tournament bracket support
- [ ] NFT rewards integration
- [ ] Staking mechanisms
- [ ] DAO governance for fee adjustments

## ⚠️ Disclaimer

This smart contract is provided as-is. While it has been thoroughly tested, it has not been formally audited. Use at your own risk. Always test on testnets before mainnet deployment.

---

**Built with ❤️ by the Flamingo Team**