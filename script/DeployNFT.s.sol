// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/NFT.sol";

contract DeployNFT is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Address of the already deployed CarbonCreditToken
        // Replace this with the correct address if it changes
        address carbonCreditTokenAddress = 0xcd0b420f1ab141c0D411E43f23F68d6A80650e90;

        vm.startBroadcast(deployerPrivateKey);

        RetirementCertificateNFT nft = new RetirementCertificateNFT(carbonCreditTokenAddress);
        console.log("RetirementCertificateNFT deployed at:", address(nft));

        vm.stopBroadcast();
    }
}
