"use client";

import { useState, useEffect } from "react";
import { ethers } from "ethers";
import { motion } from "framer-motion";

interface WalletConnectionProps {
    onConnect: (provider: ethers.BrowserProvider, signer: ethers.JsonRpcSigner, address: string) => void;
}

export default function WalletConnection({ onConnect }: WalletConnectionProps) {
    const [address, setAddress] = useState<string>("");
    const [isConnecting, setIsConnecting] = useState(false);

    // Check if wallet is already connected
    // Auto-connect removed to allow manual wallet selection
    // The user must click "Connect Wallet" to initiate connection.

    const connectWallet = async () => {
        if (typeof window.ethereum === "undefined") {
            alert("Please install MetaMask!");
            return;
        }

        setIsConnecting(true);
        try {
            // Force permission prompt to allow user to select account
            try {
                await window.ethereum.request({
                    method: "wallet_requestPermissions",
                    params: [{ eth_accounts: {} }],
                });
            } catch (error: any) {
                console.log("User cancelled permission request");
                setIsConnecting(false);
                return;
            }

            const provider = new ethers.BrowserProvider(window.ethereum);

            // Request network switch to Sepolia
            try {
                await window.ethereum.request({
                    method: 'wallet_switchEthereumChain',
                    params: [{ chainId: '0xaa36a7' }], // 11155111 in hex
                });
            } catch (switchError: any) {
                // This error code indicates that the chain has not been added to MetaMask.
                if (switchError.code === 4902) {
                    try {
                        await window.ethereum.request({
                            method: 'wallet_addEthereumChain',
                            params: [
                                {
                                    chainId: '0xaa36a7',
                                    chainName: 'Sepolia',
                                    nativeCurrency: {
                                        name: 'Sepolia Eth',
                                        symbol: 'SEP',
                                        decimals: 18,
                                    },
                                    rpcUrls: ['https://rpc.sepolia.org'],
                                },
                            ],
                        });
                    } catch (addError) {
                        console.error("Failed to add Sepolia network:", addError);
                    }
                } else {
                    console.error("Failed to switch network:", switchError);
                }
            }

            await provider.send("eth_requestAccounts", []);
            const signer = await provider.getSigner();
            const addr = await signer.getAddress();
            setAddress(addr);
            onConnect(provider, signer, addr);
        } catch (error) {
            console.error("Error connecting wallet:", error);
        } finally {
            setIsConnecting(false);
        }
    };

    return (
        <motion.div
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            className="flex items-center gap-4"
        >
            {address ? (
                <div className="bg-slate-800 px-4 py-2 rounded-full border border-slate-700 flex items-center gap-2">
                    <div className="w-2 h-2 rounded-full bg-green-500"></div>
                    <span className="font-mono text-sm text-slate-300">
                        {address.slice(0, 6)}...{address.slice(-4)}
                    </span>
                </div>
            ) : (
                <button
                    onClick={connectWallet}
                    disabled={isConnecting}
                    className="btn btn-primary"
                >
                    {isConnecting ? "Connecting..." : "Connect Wallet"}
                </button>
            )}
        </motion.div>
    );
}
