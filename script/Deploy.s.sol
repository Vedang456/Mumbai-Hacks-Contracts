// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Main.sol";
import "../src/Auction.sol";
import "../src/NFT.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Carbon Credit Token
        // Placeholder URI - should be updated with actual metadata service URL
        string memory uri = "https://api.terra-nova.com/metadata/{id}.json";
        CarbonCreditToken token = new CarbonCreditToken(uri);
        console.log("CarbonCreditToken deployed at:", address(token));

        // 2. Deploy Retirement Certificate NFT
        RetirementCertificateNFT nft = new RetirementCertificateNFT(address(token));
        console.log("RetirementCertificateNFT deployed at:", address(nft));

        // 3. Deploy Marketplace
        CarbonCreditMarketplace marketplace = new CarbonCreditMarketplace(address(token));
        console.log("CarbonCreditMarketplace deployed at:", address(marketplace));

        // Setup permissions
        // Grant Market contract approval to transfer tokens? 
        // Typically users approve the marketplace, but if the marketplace needs special roles:
        
        // The NFT contract mints certificates, but burns/transfers 1155s.
        // It needs to be able to transfer 1155s from the user. User must setApprovalForAll on the 1155 token for the NFT contract.
        
        vm.stopBroadcast();
    }
}

