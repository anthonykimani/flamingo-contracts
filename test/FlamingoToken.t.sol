// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FlamingoToken.sol";

contract FlamingoTokenWithExtensionsTest is Test {
    FlamingoTokenWithExtensions public token;

    address public owner;
    address public alice;
    address public bob;
    address public communityWallet;
    address public projectWallet;
    address public liquidityWallet;
    address public teamWallet;

    uint256 constant TOTAL_SUPPLY = 100_000_000_000 * 10 ** 18;
    uint256 constant CLIFF_DURATION = 180 days; // 6 months
    uint256 constant VESTING_DURATION = 365 days; // 12 months

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        communityWallet = makeAddr("community");
        projectWallet = makeAddr("project");
        liquidityWallet = makeAddr("liquidity");
        teamWallet = makeAddr("team");

        token = new FlamingoTokenWithExtensions(
            "Flamingo",
            "FLAMINGO",
            "Quiz rewards token",
            "https://t.me/flamingo",
            "https://flamingo.app",
            "https://x.com/flamingo",
            "https://warpcast.com/flamingo"
        );
    }

    // ============ Initialization Tests ============

    function testInitialSupply() public view {
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(address(token)), TOTAL_SUPPLY);
    }

    function testAllocations() public view {
        assertEq(token.COMMUNITY_ALLOCATION(), 30_000_000_000 * 10 ** 18);
        assertEq(token.TEAM_ALLOCATION(), 20_000_000_000 * 10 ** 18);
        assertEq(token.PROJECT_ALLOCATION(), 30_000_000_000 * 10 ** 18);
        assertEq(token.LIQUIDITY_ALLOCATION(), 20_000_000_000 * 10 ** 18);
    }

    // ============ Distribution Tests ============

    function testDistributeAllocations() public {
        token.distributeAllocations(
            communityWallet,
            projectWallet,
            liquidityWallet
        );

        assertEq(
            token.balanceOf(communityWallet),
            token.COMMUNITY_ALLOCATION()
        );
        assertEq(token.balanceOf(projectWallet), token.PROJECT_ALLOCATION());
        assertEq(
            token.balanceOf(liquidityWallet),
            token.LIQUIDITY_ALLOCATION()
        );

        // Team allocation stays in contract for vesting
        assertEq(token.balanceOf(address(token)), token.TEAM_ALLOCATION());
    }

    function testCannotDistributeToZeroAddress() public {
        vm.expectRevert("Invalid community wallet");
        token.distributeAllocations(address(0), projectWallet, liquidityWallet);
    }

    function testOnlyOwnerCanDistribute() public {
        vm.prank(alice);
        vm.expectRevert();
        token.distributeAllocations(
            communityWallet,
            projectWallet,
            liquidityWallet
        );
    }

    // ============ Vesting Tests ============

    function testCreateVesting() public {
        uint256 amount = token.TEAM_ALLOCATION();

        token.createVesting(
            teamWallet,
            amount,
            CLIFF_DURATION,
            VESTING_DURATION
        );

        (
            uint256 totalAmount,
            uint256 released,
            uint256 startTime,
            uint256 cliffDuration,
            uint256 vestingDuration
        ) = token.vestingSchedules(teamWallet);

        assertEq(totalAmount, amount);
        assertEq(released, 0);
        assertEq(startTime, block.timestamp);
        assertEq(cliffDuration, CLIFF_DURATION);
        assertEq(vestingDuration, VESTING_DURATION);
    }

    function testCannotReleaseBeforeCliff() public {
        token.createVesting(
            teamWallet,
            token.TEAM_ALLOCATION(),
            CLIFF_DURATION,
            VESTING_DURATION
        );

        // Try to release before cliff
        vm.warp(block.timestamp + 90 days); // 3 months (before 6 month cliff)

        vm.prank(teamWallet);
        vm.expectRevert("No tokens to release");
        token.release();
    }

    function testReleaseAfterCliff() public {
        uint256 amount = token.TEAM_ALLOCATION();
        token.createVesting(
            teamWallet,
            amount,
            CLIFF_DURATION,
            VESTING_DURATION
        );

        // Warp to after cliff but before full vesting
        vm.warp(block.timestamp + CLIFF_DURATION + 180 days); // 6 months into vesting

        uint256 releasable = token.releasableAmount(teamWallet);
        assertGt(releasable, 0);
        assertLt(releasable, amount);

        vm.prank(teamWallet);
        token.release();

        assertEq(token.balanceOf(teamWallet), releasable);
    }

    function testFullVesting() public {
        uint256 amount = token.TEAM_ALLOCATION();
        token.createVesting(
            teamWallet,
            amount,
            CLIFF_DURATION,
            VESTING_DURATION
        );

        // Warp to full vesting
        vm.warp(block.timestamp + CLIFF_DURATION + VESTING_DURATION);

        assertEq(token.releasableAmount(teamWallet), amount);

        vm.prank(teamWallet);
        token.release();

        assertEq(token.balanceOf(teamWallet), amount);
        assertEq(token.releasableAmount(teamWallet), 0);
    }

    function testPartialReleases() public {
        uint256 amount = token.TEAM_ALLOCATION();
        token.createVesting(
            teamWallet,
            amount,
            CLIFF_DURATION,
            VESTING_DURATION
        );

        // First release (after cliff + 6 months = halfway through vesting)
        vm.warp(block.timestamp + CLIFF_DURATION + 180 days);
        vm.prank(teamWallet);
        token.release();
        uint256 firstRelease = token.balanceOf(teamWallet);

        // Second release (after another 6 months = full vesting)
        vm.warp(block.timestamp + 185 days); // 180 + 5 extra days to ensure we're past full vesting
        vm.prank(teamWallet);
        token.release();
        uint256 totalReceived = token.balanceOf(teamWallet);

        // The total should equal the full allocation (with tiny rounding tolerance)
        assertApproxEqAbs(totalReceived, amount, 1e18); // Within 1 token tolerance
        assertGt(firstRelease, 0); // First release should be non-zero
        assertGt(totalReceived, firstRelease); // Second release should increase total
    }

    function testCannotCreateDuplicateVesting() public {
        token.createVesting(teamWallet, 1000, CLIFF_DURATION, VESTING_DURATION);

        vm.expectRevert("Vesting already exists");
        token.createVesting(teamWallet, 2000, CLIFF_DURATION, VESTING_DURATION);
    }

    // ============ Airdrop Tests ============

    function testSetAirdropAllocations() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = teamWallet;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1_000_000 * 10 ** 18;
        amounts[1] = 2_000_000 * 10 ** 18;
        amounts[2] = 3_000_000 * 10 ** 18;

        token.setAirdropAllocations(recipients, amounts);

        assertEq(token.airdropAllocations(alice), amounts[0]);
        assertEq(token.airdropAllocations(bob), amounts[1]);
        assertEq(token.airdropAllocations(teamWallet), amounts[2]);
    }

    function testClaimAirdrop() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000_000 * 10 ** 18;

        token.setAirdropAllocations(recipients, amounts);

        vm.prank(alice);
        token.claimAirdrop();

        assertEq(token.balanceOf(alice), amounts[0]);
        assertTrue(token.airdropClaimed(alice));
    }

    function testCannotClaimAirdropTwice() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000_000 * 10 ** 18;

        token.setAirdropAllocations(recipients, amounts);

        vm.startPrank(alice);
        token.claimAirdrop();

        vm.expectRevert("Already claimed");
        token.claimAirdrop();
        vm.stopPrank();
    }

    function testCannotClaimWithoutAllocation() public {
        vm.prank(alice);
        vm.expectRevert("No allocation");
        token.claimAirdrop();
    }

    function testMultipleAirdropClaims() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = teamWallet;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1_000_000 * 10 ** 18;
        amounts[1] = 2_000_000 * 10 ** 18;
        amounts[2] = 3_000_000 * 10 ** 18;

        token.setAirdropAllocations(recipients, amounts);

        vm.prank(alice);
        token.claimAirdrop();

        vm.prank(bob);
        token.claimAirdrop();

        assertEq(token.balanceOf(alice), amounts[0]);
        assertEq(token.balanceOf(bob), amounts[1]);
        assertFalse(token.airdropClaimed(teamWallet));
    }

    // ============ Complex Scenarios ============

    function testFullTokenomicsWorkflow() public {
        // 1. Distribute allocations
        token.distributeAllocations(
            communityWallet,
            projectWallet,
            liquidityWallet
        );

        // 2. Create team vesting
        token.createVesting(
            teamWallet,
            token.TEAM_ALLOCATION(),
            CLIFF_DURATION,
            VESTING_DURATION
        );

        // 3. Set airdrops (from community allocation)
        vm.startPrank(communityWallet);
        token.transfer(owner, 10_000_000 * 10 ** 18); // Transfer back to owner for airdrop
        vm.stopPrank();

        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5_000_000 * 10 ** 18;
        amounts[1] = 5_000_000 * 10 ** 18;

        token.transfer(address(token), 10_000_000 * 10 ** 18);
        token.setAirdropAllocations(recipients, amounts);

        // 4. Users claim airdrops
        vm.prank(alice);
        token.claimAirdrop();

        // 5. Time passes, team vests
        vm.warp(block.timestamp + CLIFF_DURATION + VESTING_DURATION);

        vm.prank(teamWallet);
        token.release();

        // Verify final state
        assertEq(token.balanceOf(alice), 5_000_000 * 10 ** 18);
        assertEq(token.balanceOf(teamWallet), token.TEAM_ALLOCATION());
        assertGt(token.balanceOf(communityWallet), 0);
    }

    // ============ Gas Benchmarks ============

    function testGasDistribute() public {
        uint256 gasBefore = gasleft();
        token.distributeAllocations(
            communityWallet,
            projectWallet,
            liquidityWallet
        );
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas for distribute", gasUsed);
    }

    function testGasClaimAirdrop() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000_000 * 10 ** 18;

        token.setAirdropAllocations(recipients, amounts);

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        token.claimAirdrop();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas for airdrop claim", gasUsed);
    }

    function testGasReleaseVesting() public {
        token.createVesting(
            teamWallet,
            token.TEAM_ALLOCATION(),
            CLIFF_DURATION,
            VESTING_DURATION
        );
        vm.warp(block.timestamp + CLIFF_DURATION + 180 days);

        vm.prank(teamWallet);
        uint256 gasBefore = gasleft();
        token.release();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas for vesting release", gasUsed);
    }
}
