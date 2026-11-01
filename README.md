# Charity Donation Tracker

A donation escrow where every donation in and every payment out is visible on-chain. Donors give POL or USDC. Funds leave the contract only to pre-registered vendors, only with 2-of-3 admin approval. New vendors are only added through a 48-hour timelock.

**Target network:** Polygon Amoy testnet · **Stack:** Solidity, Foundry, plain HTML/CSS/JS + ethers v6

> **v2.** The first version of this repo was a Hardhat + Next.js prototype. This version is a from-scratch rebuild as a Foundry project, with a timelock-gated vendor registry and multisig payouts.

## How the contracts fit together

```
            schedules (48h delay)              executes after delay
 VendorRegistry ─────────────────► Timelock ─────────────────────► VendorRegistry.execute()
       ▲                                                              (vendor is now registered)
       │ isRegistered(vendor)?
       │
 CharityDonationTracker
   donateETH / donateUSDC         ← anyone
   proposePayment                 ← any admin, vendor must be registered
   approvePayment                 ← 2 of 3 admins; 2nd approval reserves the funds
   executePayment                 ← any admin, after approval
```

| Contract | Responsibility |
|---|---|
| `Timelock.sol` | Generic delay queue. Operations move `Unset → Waiting → Ready → Done`. `Ready` is computed from `block.timestamp`, never stored. Separate proposer, canceller and executor roles. |
| `VendorRegistry.sol` | Whitelist of vendors who can be paid. Registration goes through the Timelock, so a new vendor is publicly visible for 48 hours before they can receive funds. |
| `Donations.sol` | Holds donations. Tracks per-donor history, and separates *allocated* funds from funds *reserved* for approved payments, so two approved payments can never spend the same money. |

### Why a timelock on vendor registration?
If an admin key is compromised, the attacker's fastest path to the money is "register my wallet as a vendor, then pay it." The 48-hour delay turns that into a public, visible event that donors and other admins can react to.

## Running it

**Contracts**

```bash
forge install            # forge-std + OpenZeppelin (versions pinned in foundry.lock)
forge build
forge test -vv
```

**Frontend**

1. Deploy the contracts to Amoy and paste the addresses into `frontend/config.js`.
2. Serve the folder (browsers block wallets and ES modules on `file://`):
   ```bash
   cd frontend && python3 -m http.server 8080
   ```
3. Open http://localhost:8080.

The dashboard reads from a public RPC, so **anyone can audit the ledger without a wallet.** A wallet is only needed to donate, and the admin panel only appears for the three admin addresses.

If you change a contract's interface, regenerate the ABI files:
```bash
forge build
jq '.abi' out/Donations.sol/CharityDonationTracker.json > frontend/abi/CharityDonationTracker.json
jq '.abi' out/VendorRegistry.sol/vendorRegistry.json   > frontend/abi/VendorRegistry.json
```

## Known limitations

Listed here on purpose. These are the next things to fix.

1. **Vendor registration can't be cancelled in a real deployment.** `Timelock` stores one role per address, so the registry can't be both proposer and canceller. `cancelRegistration` also rebuilds the operation hash with the vendor name, which isn't stored until execution, so it would hash a different ID.
2. **Payment proposals can't be cancelled or expire.** A proposal that never gets a second approval stays open forever. An approved one that's never executed keeps its funds reserved forever.
3. **`fundraisingTarget` has no unit.** The frontend assumes USDC and only counts USDC toward the progress bar. Combining POL and USDC needs a price feed.
4. **"ETH" naming on Polygon.** `donateETH` / `totalETHDonations` actually hold POL on this chain.
5. **Timelock salt is a constant**, so an identical operation can never be scheduled twice.
6. **Unit tests cover Timelock and VendorRegistry. `Donations.sol` has no tests yet.**
