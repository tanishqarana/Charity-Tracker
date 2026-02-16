import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
// Only include the key if it looks like a valid 32-byte hex string
const accounts = PRIVATE_KEY.length === 64 || PRIVATE_KEY.length === 66
    ? [PRIVATE_KEY.startsWith("0x") ? PRIVATE_KEY : `0x${PRIVATE_KEY}`]
    : [];

const config: HardhatUserConfig = {
    solidity: "0.8.24",
    networks: {
        sepolia: {
            url: process.env.ALCHEMY_SEPOLIA_URL || "",
            accounts,
        },
    },
};

export default config;

