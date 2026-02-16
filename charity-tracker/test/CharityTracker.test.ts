import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("CharityTracker", function () {
    // ── Fixture ──────────────────────────────────────────────────
    async function deployFixture() {
        const [owner, donor1, donor2] = await ethers.getSigners();

        const CharityTracker = await ethers.getContractFactory("CharityTracker");
        const charityTracker = await CharityTracker.deploy();
        await charityTracker.waitForDeployment();

        return { charityTracker, owner, donor1, donor2 };
    }

    // ── Deployment ───────────────────────────────────────────────
    describe("Deployment", function () {
        it("should set the deployer as owner", async function () {
            const { charityTracker, owner } = await loadFixture(deployFixture);
            expect(await charityTracker.owner()).to.equal(owner.address);
        });

        it("should initialize totalDonations to 0", async function () {
            const { charityTracker } = await loadFixture(deployFixture);
            expect(await charityTracker.totalDonations()).to.equal(0n);
        });
    });

    // ── Donations ────────────────────────────────────────────────
    describe("Donations", function () {
        it("should accept a valid donation", async function () {
            const { charityTracker, donor1 } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("1.0");

            await expect(
                charityTracker.connect(donor1).donate({ value: amount })
            ).to.not.be.reverted;
        });

        it("should update totalDonations after a donation", async function () {
            const { charityTracker, donor1 } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("0.5");

            await charityTracker.connect(donor1).donate({ value: amount });
            expect(await charityTracker.totalDonations()).to.equal(amount);
        });

        it("should update the donor's mapping correctly", async function () {
            const { charityTracker, donor1 } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("0.5");

            await charityTracker.connect(donor1).donate({ value: amount });
            expect(await charityTracker.donations(donor1.address)).to.equal(amount);
        });

        it("should emit DonationReceived event", async function () {
            const { charityTracker, donor1 } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("0.25");

            await expect(charityTracker.connect(donor1).donate({ value: amount }))
                .to.emit(charityTracker, "DonationReceived")
                .withArgs(donor1.address, amount);
        });

        it("should revert if donation amount is zero", async function () {
            const { charityTracker, donor1 } = await loadFixture(deployFixture);

            await expect(
                charityTracker.connect(donor1).donate({ value: 0 })
            ).to.be.revertedWith("Donation amount must be greater than 0");
        });

        it("should track multiple donors independently", async function () {
            const { charityTracker, donor1, donor2 } = await loadFixture(deployFixture);
            const amount1 = ethers.parseEther("1.0");
            const amount2 = ethers.parseEther("2.0");

            await charityTracker.connect(donor1).donate({ value: amount1 });
            await charityTracker.connect(donor2).donate({ value: amount2 });

            expect(await charityTracker.donations(donor1.address)).to.equal(amount1);
            expect(await charityTracker.donations(donor2.address)).to.equal(amount2);
            expect(await charityTracker.totalDonations()).to.equal(amount1 + amount2);
        });

        it("should accumulate multiple donations from the same donor", async function () {
            const { charityTracker, donor1 } = await loadFixture(deployFixture);
            const amount1 = ethers.parseEther("0.5");
            const amount2 = ethers.parseEther("0.3");

            await charityTracker.connect(donor1).donate({ value: amount1 });
            await charityTracker.connect(donor1).donate({ value: amount2 });

            expect(await charityTracker.donations(donor1.address)).to.equal(amount1 + amount2);
            expect(await charityTracker.totalDonations()).to.equal(amount1 + amount2);
        });
    });

    // ── Withdrawals ──────────────────────────────────────────────
    describe("Withdrawals", function () {
        it("should allow owner to withdraw the full balance", async function () {
            const { charityTracker, owner, donor1 } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("2.0");

            await charityTracker.connect(donor1).donate({ value: amount });

            await expect(
                charityTracker.connect(owner).withdraw()
            ).to.changeEtherBalance(owner, amount);
        });

        it("should emit FundsWithdrawn event", async function () {
            const { charityTracker, owner, donor1 } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("1.0");

            await charityTracker.connect(donor1).donate({ value: amount });

            await expect(charityTracker.connect(owner).withdraw())
                .to.emit(charityTracker, "FundsWithdrawn")
                .withArgs(owner.address, amount);
        });

        it("should revert if a non-owner tries to withdraw", async function () {
            const { charityTracker, donor1 } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("1.0");

            await charityTracker.connect(donor1).donate({ value: amount });

            await expect(
                charityTracker.connect(donor1).withdraw()
            ).to.be.revertedWithCustomError(charityTracker, "OwnableUnauthorizedAccount");
        });

        it("should revert if contract balance is zero", async function () {
            const { charityTracker, owner } = await loadFixture(deployFixture);

            await expect(
                charityTracker.connect(owner).withdraw()
            ).to.be.revertedWith("No funds to withdraw");
        });

        it("should leave contract with zero balance after withdrawal", async function () {
            const { charityTracker, donor1, owner } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("1.5");

            await charityTracker.connect(donor1).donate({ value: amount });
            await charityTracker.connect(owner).withdraw();

            const contractBalance = await ethers.provider.getBalance(
                await charityTracker.getAddress()
            );
            expect(contractBalance).to.equal(0n);
        });
    });

    // ── getDonationCount ─────────────────────────────────────────
    describe("getDonationCount", function () {
        it("should return the correct donation amount for a donor", async function () {
            const { charityTracker, donor1 } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("0.75");

            await charityTracker.connect(donor1).donate({ value: amount });
            expect(await charityTracker.getDonationCount(donor1.address)).to.equal(amount);
        });

        it("should return 0 for a non-donor address", async function () {
            const { charityTracker, donor2 } = await loadFixture(deployFixture);
            expect(await charityTracker.getDonationCount(donor2.address)).to.equal(0n);
        });
    });
});
