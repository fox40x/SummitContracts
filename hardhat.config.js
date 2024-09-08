require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-web3");
require("dotenv").config()
require("@onmychain/hardhat-uniswap-v2-deploy-plugin");

const {
  MAINNET_RPC_URL,
  PRIVATE_KEY,
  ETHERSCAN_API_KEY,
  SEPOLIA_URL,
} = process.env;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: 'hardhat',
  solidity: "0.8.4",
  networks: {
    hardhat: {
      accounts: {
        count: 170
      },
      // chainId: 1,
      // forking: {
      //   url: MAINNET_RPC_URL,
      //   blockNumber: 13916420
      // }
    },
    mainnet: {
      url: MAINNET_RPC_URL,
      accounts: [PRIVATE_KEY]
    },
    sepolia: {
      url: SEPOLIA_URL,
      accounts: [PRIVATE_KEY]
    }
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY
  },
  // gasReporter: {
  //   enabled: true
  // }
};