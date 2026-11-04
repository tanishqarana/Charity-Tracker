// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Timelock} from "../src/Timelock.sol";
import {vendorRegistry} from "../src/VendorRegistry.sol";
import {CharityDonationTracker} from "../src/Donations.sol";

/// Deploys Timelock -> VendorRegistry -> CharityDonationTracker and wires them together.
///
/// THE CHICKEN-AND-EGG PROBLEM
/// Timelock's constructor needs the registry's address (the registry is its proposer).
/// The registry's constructor needs the Timelock's address.
/// Solution: a contract's address is fully determined by (deployer, deployer's nonce).
/// So before deploying anything, we PREDICT the address the registry will get
/// (it will be the deployer's 2nd deployment = current nonce + 1), give that to the
/// Timelock, then deploy the registry and check the prediction was right.
///
/// Usage (Amoy):
///   source .env
///   forge script script/Deploy.s.sol --rpc-url amoy --broadcast --verify
contract Deploy is Script {
    // Circle's official testnet USDC on Polygon Amoy (developers.circle.com/stablecoins/usdc-contract-addresses).
    // Donors can get it free from faucet.circle.com.
    address constant AMOY_USDC = 0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582;

    // All settings in one struct: a single function with this many local
    // variables hits Solidity's "stack too deep" limit.
    struct Config {
        uint256 deployerKey;
        address deployer;
        address admin1;
        address admin2;
        address admin3;
        address tlCanceller;
        address tlExecutor;
        address registryProposer;
        address usdc;
        uint256 target;
        address demoVendor;
        string demoVendorName;
    }

    function loadConfig() internal view returns (Config memory c) {
        c.deployerKey = vm.envUint("PRIVATE_KEY");
        c.deployer = vm.addr(c.deployerKey);

        // Three distinct admins for the 2-of-3 payout approvals.
        // admin1 defaults to the deployer; admin2 and admin3 must be set in .env.
        c.admin1 = vm.envOr("ADMIN1", c.deployer);
        c.admin2 = vm.envAddress("ADMIN2");
        c.admin3 = vm.envAddress("ADMIN3");

        // Who may cancel / execute queued timelock operations. Default: deployer.
        // (Canceller is a person, not the registry: see the note at the bottom.)
        c.tlCanceller = vm.envOr("TIMELOCK_CANCELLER", c.deployer);
        c.tlExecutor = vm.envOr("TIMELOCK_EXECUTOR", c.deployer);

        // Who may call registry.register(). Default: deployer.
        c.registryProposer = vm.envOr("REGISTRY_PROPOSER", c.deployer);

        c.usdc = vm.envOr("USDC_ADDRESS", AMOY_USDC);

        // fundraisingTarget has no unit in the contract. The frontend reads it as
        // USDC (6 decimals), so 1000e6 = 1,000 USDC. Keep the two in agreement.
        c.target = vm.envOr("FUNDRAISING_TARGET", uint256(1_000e6));

        // Optional: queue a first vendor right away, because registration
        // takes 48 REAL hours on a live chain. Leave unset to skip.
        c.demoVendor = vm.envOr("DEMO_VENDOR", address(0));
        c.demoVendorName = vm.envOr("DEMO_VENDOR_NAME", string("Demo Vendor"));
    }

    function run() external {
        Config memory c = loadConfig();
        uint256 deployBlock = block.number;

        vm.startBroadcast(c.deployerKey);

        // Nonce now = next deployment (Timelock). Registry is the one after that.
        address predictedRegistry = vm.computeCreateAddress(c.deployer, vm.getNonce(c.deployer) + 1);

        Timelock timelock = new Timelock(predictedRegistry, c.tlCanceller, c.tlExecutor);
        vendorRegistry registry = new vendorRegistry(address(timelock), c.registryProposer);
        require(address(registry) == predictedRegistry, "Registry address prediction failed");

        CharityDonationTracker donations = new CharityDonationTracker(
            c.admin1, c.admin2, c.admin3, c.usdc, address(registry), c.target
        );

        if (c.demoVendor != address(0)) {
            require(c.registryProposer == c.deployer, "DEMO_VENDOR needs REGISTRY_PROPOSER = deployer");
            registry.register(c.demoVendor, c.demoVendorName);
        }

        vm.stopBroadcast();

        console.log("Timelock:              ", address(timelock));
        console.log("VendorRegistry:        ", address(registry));
        console.log("CharityDonationTracker:", address(donations));
        console.log("USDC:                  ", c.usdc);
        console.log("");
        console.log("Paste into frontend/config.js:");
        console.log("  donationsAddress:", address(donations));
        console.log("  registryAddress: ", address(registry));
        console.log("  deployBlock:     ", deployBlock);
        if (c.demoVendor != address(0)) {
            console.log("");
            console.log("Demo vendor queued. Executable after (unix time):", block.timestamp + 48 hours);
            console.log("Get the operationId from the `scheduled` event on the Timelock, then the");
            console.log("executor calls Timelock.execute(operationId) once 48 hours have passed.");
        }
    }
}

// NOTE ON ROLES
// Timelock currently stores ONE role per address (mapping(address => string)), so the
// registry can't be both proposer and canceller. The registry gets proposer (it must
// call schedule()); cancelling is done by a person calling Timelock.cancel(operationId)
// directly. Once Timelock supports multiple roles per address, TIMELOCK_CANCELLER can
// be set to the registry so cancelRegistration() works too.
