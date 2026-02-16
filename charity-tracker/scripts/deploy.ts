
import hre from "hardhat";

async function main() {
    const CharityTracker = await hre.ethers.getContractFactory("CharityTracker");
    const charityTracker = await CharityTracker.deploy();

    await charityTracker.waitForDeployment();

    console.log("CharityTracker deployed to:", await charityTracker.getAddress());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
