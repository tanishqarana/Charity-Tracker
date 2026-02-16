import { ethers } from "hardhat";
import { CharityTracker } from "../typechain-types";

async function main() {
    const [signer] = await ethers.getSigners();
    const contractAddress = "0x6a3A9A8CD77C7F03D35e74d362573ECb65F35c2b"; // CharityTracker
    const CharityTracker = await ethers.getContractFactory("CharityTracker");
    const contract = CharityTracker.attach(contractAddress) as CharityTracker;

    // Get Fee Data (EIP-1559)
    const feeData = await ethers.provider.getFeeData();
    const gasPrice = feeData.gasPrice ?? 1n; // Legacy fallback
    const maxFeePerGas = feeData.maxFeePerGas ?? gasPrice;

    console.log(`Current Gas Price: ${ethers.formatUnits(gasPrice, "gwei")} gwei`);

    // Estimate Gas for donation
    const donationAmount = ethers.parseEther("0.001");
    try {
        const gasEstimate = await contract.connect(signer).donate.estimateGas({ value: donationAmount });
        console.log(`Estimated Gas Units: ${gasEstimate.toString()}`);

        const costWei = gasEstimate * maxFeePerGas;
        const costEth = ethers.formatEther(costWei);

        console.log(`Estimated Transaction Cost: ${costEth} ETH`);

        // Assuming ETH price is roughly $2600 for context (hardcoded for estimation)
        const ethPrice = 2600;
        const costUsd = parseFloat(costEth) * ethPrice;
        console.log(`Estimated Cost in USD: ~$${costUsd.toFixed(4)}`);
    } catch (error) {
        console.error("Error estimating gas:", error);
        // Fallback if estimate fails (likely due to insufficient funds)
        console.log("Could not estimate exact gas (likely 0 balance).");
        console.log("Typical Cost: ~50,000 gas units * gas price");
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
