// Charity Donation Tracker — plain JS frontend (ethers v6, no build step).
//
// Two ways to talk to the chain:
//   reader  – a JsonRpcProvider on the public RPC. Works with NO wallet, so
//             anyone can audit the ledger. That is the whole point of the product.
//   signer  – from the user's wallet (MetaMask). Only needed to SEND transactions.

import { ethers } from "https://cdn.jsdelivr.net/npm/ethers@6.13.4/dist/ethers.min.js";
import { CONFIG } from "./config.js";

const ERC20_ABI = [
  "function decimals() view returns (uint8)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
];
const STATUS = ["Proposed", "Approved", "Executed"]; // mirrors enum PaymentStatus

const $ = (id) => document.getElementById(id);
const short = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;

const state = {
  reader: null,
  signer: null,
  account: null,
  donations: null, // contract bound to reader (or signer once connected)
  registry: null,
  usdc: null,
  usdcAddress: null,
  usdcDecimals: 6,
  admins: [],
  isAdmin: false,
  asset: "native", // selected donate tab
};

// ───────────────────────── boot ─────────────────────────

async function boot() {
  document.querySelectorAll(".native-sym").forEach((el) => (el.textContent = CONFIG.nativeSymbol));
  $("tSuffix").textContent = CONFIG.targetSymbol;

  if (CONFIG.donationsAddress === ethers.ZeroAddress) {
    $("configBanner").hidden = false;
    $("feed").innerHTML = `<li class="muted">Waiting for contract addresses.</li>`;
    wireUi();
    return;
  }

  setLink("donationsLink", CONFIG.donationsAddress);
  setLink("registryLink", CONFIG.registryAddress);

  state.reader = new ethers.JsonRpcProvider(CONFIG.rpcUrl, CONFIG.chainId, { staticNetwork: true });
  const [donationsAbi, registryAbi] = await Promise.all([
    fetch("abi/CharityDonationTracker.json").then((r) => r.json()),
    fetch("abi/VendorRegistry.json").then((r) => r.json()),
  ]);
  state.donationsAbi = donationsAbi;
  state.donations = new ethers.Contract(CONFIG.donationsAddress, donationsAbi, state.reader);
  state.registry = new ethers.Contract(CONFIG.registryAddress, registryAbi, state.reader);

  // The USDC address is stored in the contract, so read it from there
  // instead of duplicating it in config (one source of truth).
  state.usdcAddress = await state.donations.usdcToken();
  state.usdc = new ethers.Contract(state.usdcAddress, ERC20_ABI, state.reader);
  state.usdcDecimals = Number(await state.usdc.decimals());
  state.admins = (await Promise.all([
    state.donations.admin1(), state.donations.admin2(), state.donations.admin3(),
  ])).map((a) => a.toLowerCase());

  wireUi();
  await refreshAll();
}

function wireUi() {
  $("connectBtn").onclick = connect;
  $("refreshBtn").onclick = () => refreshAll();

  document.querySelectorAll(".tab").forEach((tab) => {
    tab.onclick = () => {
      document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("active", t === tab));
      state.asset = tab.dataset.asset;
      $("donateSuffix").textContent = state.asset === "native" ? CONFIG.nativeSymbol : "USDC";
      $("usdcHint").hidden = state.asset !== "usdc";
    };
  });

  $("donateForm").onsubmit = (e) => { e.preventDefault(); donate(); };
  $("vendorForm").onsubmit = (e) => { e.preventDefault(); checkVendor(); };
  $("proposeForm").onsubmit = (e) => { e.preventDefault(); proposePayment(); };
  $("targetForm").onsubmit = (e) => { e.preventDefault(); proposeTarget(); };

  // Event delegation: one listener handles every Approve/Execute button
  // in the proposals table, even rows rendered later.
  $("proposals").onclick = (e) => {
    const btn = e.target.closest("button[data-action]");
    if (btn) paymentAction(btn.dataset.action, btn.dataset.id);
  };
  $("targetProposals").onclick = (e) => {
    const btn = e.target.closest("button[data-target-id]");
    if (btn) approveTarget(btn.dataset.targetId);
  };

  if (window.ethereum) {
    window.ethereum.on?.("accountsChanged", () => connect());
    window.ethereum.on?.("chainChanged", () => window.location.reload());
  }
}

// ───────────────────────── wallet ─────────────────────────

async function connect() {
  if (!window.ethereum) return toast("No wallet found. Install MetaMask to send transactions. You can still read the ledger without one.", "err");
  if (!state.donations) return toast("Set the contract addresses in config.js first.", "err");

  try {
    await switchChain();
    const browser = new ethers.BrowserProvider(window.ethereum);
    state.signer = await browser.getSigner();
    state.account = (await state.signer.getAddress()).toLowerCase();

    // Same contract, now with a signer attached, so calls can write.
    state.donations = state.donations.connect(state.signer);
    state.usdc = state.usdc.connect(state.signer);

    state.isAdmin = state.admins.includes(state.account);
    $("connectBtn").textContent = short(state.account);
    $("networkPill").textContent = CONFIG.chainName;
    $("networkPill").className = "pill ok";
    $("adminPanel").hidden = !state.isAdmin;
    $("actionsHead").hidden = !state.isAdmin;
    await refreshAll();
  } catch (err) {
    toast(readableError(err), "err");
  }
}

// Ask the wallet to move to our chain. If it doesn't know the chain
// (error 4902), add it first. Without this, users sign on the wrong network.
async function switchChain() {
  const chainIdHex = "0x" + CONFIG.chainId.toString(16);
  try {
    await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: chainIdHex }] });
  } catch (err) {
    if (err.code !== 4902) throw err;
    await window.ethereum.request({
      method: "wallet_addEthereumChain",
      params: [{
        chainId: chainIdHex,
        chainName: CONFIG.chainName,
        nativeCurrency: { name: CONFIG.nativeSymbol, symbol: CONFIG.nativeSymbol, decimals: 18 },
        rpcUrls: [CONFIG.rpcUrl],
        blockExplorerUrls: [CONFIG.blockExplorer],
      }],
    });
  }
}

// ───────────────────────── reads ─────────────────────────

async function refreshAll() {
  if (!state.donations) return;
  try {
    await Promise.all([loadLedger(), loadProposals(), loadFeed(), loadMyDonations(), loadTargetProposals()]);
  } catch (err) {
    toast(readableError(err), "err");
  }
}

const fmtNative = (v) => `${trim(ethers.formatEther(v))} ${CONFIG.nativeSymbol}`;
const fmtUsdc = (v) => `${trim(ethers.formatUnits(v, state.usdcDecimals))} USDC`;
const fmtAsset = (asset, v) => (asset === ethers.ZeroAddress ? fmtNative(v) : fmtUsdc(v));
// "1.500000" → "1.5", and cap long decimals for display only.
function trim(s) {
  const [i, d = ""] = s.split(".");
  const dd = d.slice(0, 6).replace(/0+$/, "");
  return Number(i).toLocaleString("en-US") + (dd ? "." + dd : "");
}

async function loadLedger() {
  const d = state.donations;
  const [ethTotal, ethAlloc, ethRes, ethAvail, usdcTotal, usdcAlloc, usdcRes, usdcAvail, target] = await Promise.all([
    d.totalETHDonations(), d.allocatedETH(), d.reservedETH(), d.getAvailableETH(),
    d.totalUSDCDonations(), d.allocatedUSDC(), d.reservedUSDC(), d.getAvailableUSDC(),
    d.fundraisingTarget(),
  ]);
  $("ethTotal").textContent = fmtNative(ethTotal);
  $("ethAllocated").textContent = fmtNative(ethAlloc);
  $("ethReserved").textContent = fmtNative(ethRes);
  $("ethAvailable").textContent = fmtNative(ethAvail);
  $("usdcTotal").textContent = fmtUsdc(usdcTotal);
  $("usdcAllocated").textContent = fmtUsdc(usdcAlloc);
  $("usdcReserved").textContent = fmtUsdc(usdcRes);
  $("usdcAvailable").textContent = fmtUsdc(usdcAvail);

  $("targetValue").textContent = `${trim(ethers.formatUnits(target, CONFIG.targetDecimals))} ${CONFIG.targetSymbol}`;
  $("usdcRaisedForTarget").textContent = trim(ethers.formatUnits(usdcTotal, state.usdcDecimals));
  // BigInt maths: never convert token amounts to JS Number before dividing.
  const pct = target > 0n ? Number((usdcTotal * 10000n) / target) / 100 : 0;
  $("targetBar").style.width = Math.min(pct, 100) + "%";
}

async function loadProposals() {
  const count = Number(await state.donations.proposalCount());
  if (count === 0) {
    $("proposals").innerHTML = `<tr><td colspan="7" class="muted">No payment proposals yet.</td></tr>`;
    return;
  }
  const ids = Array.from({ length: count }, (_, i) => count - i); // newest first
  const rows = await Promise.all(ids.map(async (id) => {
    const p = await state.donations.getPaymentProposal(id);
    const approvedByMe = state.isAdmin ? await state.donations.hasApproved(id, state.account) : false;
    return { id, p, approvedByMe };
  }));

  $("proposals").innerHTML = rows.map(({ id, p, approvedByMe }) => {
    const status = STATUS[Number(p.status)];
    let actions = "";
    if (state.isAdmin) {
      if (status === "Proposed") actions = `<button class="btn btn-sm" data-action="approve" data-id="${id}" ${approvedByMe ? "disabled" : ""}>${approvedByMe ? "Approved" : "Approve"}</button>`;
      if (status === "Approved") actions = `<button class="btn btn-sm btn-primary" data-action="execute" data-id="${id}">Execute</button>`;
    }
    return `<tr>
      <td class="mono">${id}</td>
      <td class="mono"><a href="${CONFIG.blockExplorer}/address/${p.vendor}" target="_blank" rel="noopener">${short(p.vendor)}</a></td>
      <td>${escapeHtml(p.purpose)}</td>
      <td class="mono r">${fmtAsset(p.asset, p.amount)}</td>
      <td class="mono">${p.approvals} / 2</td>
      <td><span class="chip chip-${status}">${status}</span></td>
      ${state.isAdmin ? `<td>${actions}</td>` : ""}
    </tr>`;
  }).join("");
}

// Donations are events, not a stored list, so the public feed reads logs.
async function loadFeed() {
  try {
    const latest = await state.reader.getBlockNumber();
    const from = Math.max(CONFIG.deployBlock, latest - CONFIG.logLookback);
    const logs = await state.donations.queryFilter(state.donations.filters.DonationReceived(), from, latest);
    const recent = logs.slice(-10).reverse();
    $("feed").innerHTML = recent.length
      ? recent.map((l) => {
          const { donor, asset, amount, timestamp } = l.args;
          return `<li><span class="mono">${short(donor)}</span><span class="mono">${fmtAsset(asset, amount)}</span><span class="muted">${timeAgo(timestamp)}</span></li>`;
        }).join("")
      : `<li class="muted">No donations in the last ${CONFIG.logLookback.toLocaleString()} blocks.</li>`;
  } catch {
    $("feed").innerHTML = `<li class="muted">This RPC refused the event query. Try a different RPC URL.</li>`;
  }
}

async function loadMyDonations() {
  if (!state.account) return;
  const history = await state.donations.getDonationHistory(state.account);
  $("myDonations").innerHTML = history.length
    ? [...history].reverse().map((d) =>
        `<li><span class="mono">${fmtAsset(d.asset, d.amount)}</span><span class="muted">${new Date(Number(d.timestamp) * 1000).toLocaleString()}</span></li>`
      ).join("")
    : `<li class="muted">You haven't donated from this address yet.</li>`;
}

async function loadTargetProposals() {
  if (!state.isAdmin) return;
  const count = Number(await state.donations.targetProposalCount());
  const items = [];
  for (let id = count; id >= 1 && items.length < 5; id--) {
    const [value, approvals, mine] = await Promise.all([
      state.donations.proposedTargets(id),
      state.donations.targetApprovalCount(id),
      state.donations.hasApprovedTarget(id, state.account),
    ]);
    // The contract marks an applied proposal by overwriting it with uint256 max.
    const done = value === ethers.MaxUint256;
    const label = done ? "applied" : `${trim(ethers.formatUnits(value, CONFIG.targetDecimals))} ${CONFIG.targetSymbol}`;
    const btn = done ? "" : `<button class="btn btn-sm" data-target-id="${id}" ${mine ? "disabled" : ""}>${mine ? "Approved" : "Approve"}</button>`;
    items.push(`<li><span>Target #${id}: <span class="mono">${label}</span> <span class="muted">(${approvals}/2)</span></span>${btn}</li>`);
  }
  $("targetProposals").innerHTML = items.join("");
}

async function checkVendor() {
  const addr = $("vendorAddr").value.trim();
  const out = $("vendorResult");
  out.hidden = false;
  if (!ethers.isAddress(addr)) { out.className = "result no"; out.textContent = "That isn't a valid address."; return; }
  if (!state.registry) { out.className = "result no"; out.textContent = "Registry address not configured."; return; }
  const ok = await state.registry.isRegistered(addr);
  out.className = "result " + (ok ? "yes" : "no");
  out.textContent = ok ? "Registered. This vendor can receive payments." : "Not registered. Payments to this address will be rejected.";
}

// ───────────────────────── writes ─────────────────────────

// Every write goes through here: send → wait for it to be mined → refresh.
// Waiting for the receipt matters: "sent" is not "confirmed".
async function send(label, txPromiseFn) {
  if (!state.signer) return toast("Connect your wallet first.", "err");
  try {
    toast(`${label}: confirm in your wallet…`);
    const tx = await txPromiseFn();
    toast(`${label}: waiting for confirmation… <a href="${CONFIG.blockExplorer}/tx/${tx.hash}" target="_blank" rel="noopener">view</a>`);
    await tx.wait();
    await refreshAll(); // re-read the chain BEFORE saying "done", so the page never shows stale numbers
    toast(`${label}: done.`, "ok");
    return true;
  } catch (err) {
    toast(`${label} failed: ${readableError(err)}`, "err");
    return false;
  }
}

async function donate() {
  const raw = $("donateAmount").value.trim();
  if (state.asset === "native") {
    const value = parseAmount(raw, 18);
    if (value === null) return;
    if (await send("Donation", () => state.donations.donateETH({ value }))) $("donateAmount").value = "";
    return;
  }

  const amount = parseAmount(raw, state.usdcDecimals);
  if (amount === null) return;
  // ERC-20 tokens can't be "sent with" a call the way native POL can.
  // The contract pulls them with transferFrom, which needs your approval first.
  const allowance = await state.usdc.allowance(state.account, CONFIG.donationsAddress);
  if (allowance < amount) {
    const ok = await send("Approve USDC", () => state.usdc.approve(CONFIG.donationsAddress, amount));
    if (!ok) return;
  }
  if (await send("Donation", () => state.donations.donateUSDC(amount))) $("donateAmount").value = "";
}

async function paymentAction(action, id) {
  if (action === "approve") await send(`Approve payment #${id}`, () => state.donations.approvePayment(id));
  if (action === "execute") await send(`Execute payment #${id}`, () => state.donations.executePayment(id));
}

async function proposePayment() {
  const vendor = $("pVendor").value.trim();
  if (!ethers.isAddress(vendor)) return toast("Vendor address is not valid.", "err");
  const isNative = $("pAsset").value === "native";
  const amount = parseAmount($("pAmount").value.trim(), isNative ? 18 : state.usdcDecimals);
  if (amount === null) return;
  const asset = isNative ? ethers.ZeroAddress : state.usdcAddress;
  const ok = await send("Propose payment", () => state.donations.proposePayment(vendor, asset, amount, $("pPurpose").value.trim()));
  if (ok) $("proposeForm").reset();
}

async function proposeTarget() {
  const amount = parseAmount($("tAmount").value.trim(), CONFIG.targetDecimals);
  if (amount === null) return;
  if (await send("Propose target", () => state.donations.proposeTargetUpdate(amount))) $("targetForm").reset();
}

async function approveTarget(id) {
  await send(`Approve target #${id}`, () => state.donations.approveTargetUpdate(id));
}

// ───────────────────────── helpers ─────────────────────────

// parseUnits turns "1.5" into 1500000000000000000n using the token's decimals.
// Never do `amount * 1e18` in JS: floats lose precision.
function parseAmount(raw, decimals) {
  try {
    const v = ethers.parseUnits(raw, decimals);
    if (v <= 0n) throw new Error();
    return v;
  } catch {
    toast("Enter a positive amount (digits and one decimal point).", "err");
    return null;
  }
}

// Pull the revert string out of ethers' nested error objects.
function readableError(err) {
  if (err?.code === "ACTION_REJECTED" || err?.code === 4001) return "you rejected the request in your wallet.";
  if (err?.revert?.args?.[0]) return err.revert.args[0];
  if (err?.reason) return err.reason;
  // Custom errors / reverts that ethers couldn't decode on the first pass
  const data = err?.data ?? err?.info?.error?.data;
  if (data && state.donationsAbi) {
    try {
      const parsed = new ethers.Interface(state.donationsAbi).parseError(data);
      if (parsed) return parsed.args?.[0] ?? parsed.name;
    } catch {}
  }
  return err?.shortMessage || err?.message || String(err);
}

let toastTimer;
function toast(html, kind = "") {
  const el = $("toast");
  el.innerHTML = html;
  el.className = "banner" + (kind ? ` banner-${kind}` : "");
  el.hidden = false;
  clearTimeout(toastTimer);
  if (kind) toastTimer = setTimeout(() => (el.hidden = true), kind === "err" ? 9000 : 4000);
}

function setLink(id, addr) {
  const a = $(id);
  a.textContent = addr;
  a.href = `${CONFIG.blockExplorer}/address/${addr}`;
}

function timeAgo(ts) {
  const s = Math.max(0, Math.floor(Date.now() / 1000) - Number(ts));
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

// Purpose strings are user input stored on-chain. Escape before
// inserting into HTML, or an admin could inject script into the page.
function escapeHtml(s) {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

boot().catch((err) => toast(readableError(err), "err"));
