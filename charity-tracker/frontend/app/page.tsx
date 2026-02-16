"use client";

import { useState, useEffect } from "react";
import { ethers, Contract } from "ethers";
import WalletConnection from "../components/WalletConnection";
import DonationForm from "../components/DonationForm";
import { CONTRACT_ADDRESS } from "../utils/config";
import CharityTrackerABI from "../utils/CharityTracker.json";
import { motion } from "framer-motion";

export default function Home() {
  const [provider, setProvider] = useState<ethers.BrowserProvider | null>(null);
  const [signer, setSigner] = useState<ethers.JsonRpcSigner | null>(null);
  const [contract, setContract] = useState<Contract | null>(null);
  const [totalRaised, setTotalRaised] = useState<string>("0.0");

  const handleConnect = async (
    p: ethers.BrowserProvider,
    s: ethers.JsonRpcSigner,
    addr: string
  ) => {
    setProvider(p);
    setSigner(s);

    try {
      const charityContract = new ethers.Contract(
        CONTRACT_ADDRESS,
        CharityTrackerABI,
        s
      );
      setContract(charityContract);

      // Fetch total donations
      const total = await charityContract.totalDonations();
      setTotalRaised(ethers.formatEther(total));

      // Listen for donations
      // Note: This requires the provider to support events, which MetaMask does.
      charityContract.on("DonationReceived", (donor, amount, event) => {
        console.log("New donation:", amount);
        // Update total raised
        charityContract.totalDonations().then((t: bigint) => {
          setTotalRaised(ethers.formatEther(t));
        });
      });

    } catch (error) {
      console.error("Error setting up contract:", error);
    }
  };

  return (
    <main className="min-h-screen p-4 flex flex-col">
      <header className="container flex justify-between items-center py-6">
        <div className="flex items-center gap-2">
          <motion.div
            initial={{ rotate: -180, scale: 0 }}
            animate={{ rotate: 0, scale: 1 }}
            transition={{ type: "spring", stiffness: 260, damping: 20 }}
            className="w-8 h-8 bg-blue-500 rounded-lg"
          />
          <h1 className="font-bold text-xl tracking-tight">CharityChain</h1>
        </div>
        <WalletConnection onConnect={handleConnect} />
      </header>

      <section className="container flex-1 flex flex-col items-center justify-center text-center gap-8 py-10">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
        >
          <h1 className="title">Transparent Giving <br /> on the Blockchain</h1>
          <p className="subtitle max-w-2xl mx-auto">
            Donate ETH securely and track every transaction on the Sepolia network.
            No intermediaries, just direct impact.
          </p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.4 }}
          className="grid md:grid-cols-2 gap-8 w-full max-w-4xl"
        >
          {/* Stats Card */}
          <div className="card flex flex-col justify-center items-center text-center p-8">
            <h3 className="text-gray-400 uppercase text-sm font-semibold tracking-wider mb-2">Total Funds Raised</h3>
            <div className="text-5xl font-mono font-bold text-green-400">
              {totalRaised} <span className="text-2xl text-white">ETH</span>
            </div>
            <p className="text-sm text-gray-500 mt-4">
              Securely stored in smart contract
            </p>
          </div>

          {/* Donation Form */}
          <DonationForm contract={contract} />
        </motion.div>
      </section>

      <footer className="container text-center text-gray-600 py-6 text-sm">
        <p>&copy; 2026 CharityChain. Deployed on Sepolia.</p>
      </footer>
    </main>
  );
}
