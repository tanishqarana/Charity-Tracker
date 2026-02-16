# 🤲 Charity Donation Tracker

A decentralized application (dApp) that brings transparency to charitable giving. Users can donate ETH to the smart contract, which tracks individual contributions on-chain. The verified charity owner is the only entity capable of withdrawing the aggregated funds.

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?logo=solidity)
![Hardhat](https://img.shields.io/badge/Built%20with-Hardhat-FFdb1c?logo=hardhat)
![React](https://img.shields.io/badge/Frontend-Next.js-000000?logo=next.js)

## 🚀 Features

- **Transparent Donations:** Anyone can donate ETH, and all transactions are recorded on the blockchain.
- **Donation Tracking:** The smart contract maps every donor's address to their total contribution amount.
- **Secure Withdrawal:** Only the contract owner (the charity) can withdraw funds, protected by OpenZeppelin's `Ownable` pattern.
- **Real-time Updates:** The frontend displays the total ETH raised and updates automatically.
- **Responsive UI:** Built with Next.js and Tailwind CSS for a clean, mobile-friendly experience.

## 🛠️ Tech Stack

- **Smart Contract:** Solidity (v0.8.24)
- **Framework:** Hardhat (TypeScript)
- **Frontend:** Next.js (App Router), Tailwind CSS
- **Interaction:** Ethers.js v6
- **Network:** Ethereum Sepolia Testnet (via Alchemy)

