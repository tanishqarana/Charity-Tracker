// ─────────────────────────────────────────────────────────────
// Deployment config. Fill these in after you deploy.
// This is the ONLY file you should need to edit to point the
// frontend at a different network or a new deployment.
// ─────────────────────────────────────────────────────────────

export const CONFIG = {
  // Polygon Amoy testnet. Amoy replaced Mumbai as Polygon PoS's testnet.
  chainId: 80002,
  chainName: "Polygon Amoy",
  rpcUrl: "https://rpc-amoy.polygon.technology",
  blockExplorer: "https://amoy.polygonscan.com",

  // On Polygon the native gas token is POL, not ETH.
  // Your contract calls it "ETH" (donateETH, totalETHDonations),
  // but on this chain those functions actually move POL.
  nativeSymbol: "POL",

  // ← paste your deployed addresses here
  donationsAddress: "0x0000000000000000000000000000000000000000",
  registryAddress:  "0x0000000000000000000000000000000000000000",

  // fundraisingTarget is a bare uint256 in the contract with no unit.
  // The frontend has to assume one. USDC (6 decimals) is assumed here.
  targetSymbol: "USDC",
  targetDecimals: 6,

  // Block the Donations contract was deployed in. The donation feed
  // reads events from here onward. Public RPCs cap how many blocks
  // one eth_getLogs call can scan, so we also cap the lookback.
  deployBlock: 0,
  logLookback: 9000,
};
