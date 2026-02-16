"use client";

import { useState } from "react";
import { ethers, Contract } from "ethers";
import { motion } from "framer-motion";

interface DonationFormProps {
    contract: Contract | null;
}

export default function DonationForm({ contract }: DonationFormProps) {
    const [amount, setAmount] = useState("");
    const [isLoading, setIsLoading] = useState(false);
    const [status, setStatus] = useState<"idle" | "success" | "error">("idle");
    const [message, setMessage] = useState("");

    const handleDonate = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!contract) {
            alert("Please connect your wallet first!");
            return;
        }
        if (!amount || parseFloat(amount) <= 0) {
            alert("Please enter a valid amount");
            return;
        }

        setIsLoading(true);
        setStatus("idle");
        setMessage("");

        try {
            const parsedAmount = ethers.parseEther(amount);
            const tx = await contract.donate({ value: parsedAmount });

            setMessage("Transaction submitted. Waiting for confirmation...");
            await tx.wait();

            setStatus("success");
            setMessage(`Successfully donated ${amount} ETH! Thank you!`);
            setAmount("");
        } catch (error: any) {
            console.error(error);
            setStatus("error");

            // Check for Insufficient Funds (common code: INSUFFICIENT_FUNDS or -32000 from some RPCs)
            if (error.code === "INSUFFICIENT_FUNDS" || error.code === "CALL_EXCEPTION" || error.message?.includes("insufficient funds")) {
                setMessage("Insufficient funds for gas or donation. Please get Sepolia ETH from a faucet.");
            } else {
                setMessage(error.reason || error.message || "Transaction failed");
            }
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            className="card w-full max-w-md mx-auto"
        >
            <h2 className="text-2xl font-bold mb-4">Make a Donation</h2>
            <form onSubmit={handleDonate} className="flex flex-col gap-4">
                <div>
                    <label className="block text-sm text-gray-400 mb-1">Amount (ETH)</label>
                    <input
                        type="number"
                        step="0.0001"
                        value={amount}
                        onChange={(e) => setAmount(e.target.value)}
                        placeholder="0.01"
                        className="input"
                        disabled={isLoading || !contract}
                    />
                </div>

                <button
                    type="submit"
                    disabled={isLoading || !contract}
                    className={`btn ${status === 'error' ? 'bg-red-600' : 'btn-primary'} w-full flex justify-center items-center gap-2`}
                >
                    {isLoading ? (
                        <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                    ) : (
                        "Donate Now"
                    )}
                </button>

                {message && (
                    <motion.div
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        className={`p-3 rounded-lg text-sm ${status === "success" ? "bg-green-500/20 text-green-300" :
                            status === "error" ? "bg-red-500/20 text-red-300" :
                                "bg-blue-500/20 text-blue-300"
                            }`}
                    >
                        {message}
                    </motion.div>
                )}
            </form>
        </motion.div>
    );
}
