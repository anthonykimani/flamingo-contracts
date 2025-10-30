// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FlamingoToken.sol";

contract DeployWithExtensions is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        string memory name = vm.envOr("TOKEN_NAME", string("Flamingo"));
        string memory symbol = vm.envOr("TOKEN_SYMBOL", string("FLAMINGO"));
        string memory description = vm.envOr("TOKEN_DESCRIPTION", string("Flamingo quiz rewards token"));
        string memory telegram = vm.envOr("TELEGRAM_LINK", string("https://t.me/flamingo"));
        string memory website = vm.envOr("WEBSITE_LINK", string("https://flamingo.app"));
        string memory twitter = vm.envOr("TWITTER_LINK", string("https://x.com/flamingo"));
        string memory farcaster = vm.envOr("FARCASTER_LINK", string("https://warpcast.com/flamingo"));
        
        vm.startBroadcast(deployerPrivateKey);
        
        FlamingoTokenWithExtensions token = new FlamingoTokenWithExtensions(
            name,
            symbol,
            description,
            telegram,
            website,
            twitter,
            farcaster
        );
        
        console.log("===========================================");
        console.log("FlamingoToken (With Extensions) Deployment");
        console.log("===========================================");
        console.log("Network:", block.chainid);
        console.log("Token Address:", address(token));
        console.log("Total Supply:", token.totalSupply() / 10**18, "tokens");
        console.log("Community Allocation:", token.COMMUNITY_ALLOCATION() / 10**18, "tokens");
        console.log("Team Allocation:", token.TEAM_ALLOCATION() / 10**18, "tokens");
        console.log("Project Allocation:", token.PROJECT_ALLOCATION() / 10**18, "tokens");
        console.log("Liquidity Allocation:", token.LIQUIDITY_ALLOCATION() / 10**18, "tokens");
        console.log("===========================================");
        
        vm.stopBroadcast();
    }
}