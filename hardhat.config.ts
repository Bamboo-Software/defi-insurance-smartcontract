import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    // Avalanche Fuji Testnet
    fuji: {
      url: process.env.FUJI_RPC,
      chainId: 43113,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    //Avalanche Mainnet
    avalanche: {
      url: process.env.MAINNET_RPC,
      chainId: 43114,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      snowtrace: "snowtrace", // apiKey is not required, just set a placeholder
    },
    customChains: [
      {
        network: "snowtrace",
        chainId: 43113,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/testnet/evm/43113/etherscan",
          browserURL: "https://avalanche.testnet.localhost:8080",
        },
      },
    ],
    // apiKey: "KUQT7R21M97MUC36EUVNKEGQHUD2JE2WD3", // API key v2
    // customChains: [
    //   {
    //     network: "fuji",
    //     chainId: 43113,
    //     urls: {
    //       apiURL: "https://api-testnet.snowtrace.io/api",
    //       browserURL: "https://testnet.snowtrace.io"
    //     }
    //   }
    // ]
  },
};

export default config;
