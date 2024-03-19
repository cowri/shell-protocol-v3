require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("solidity-coverage");
const fs = require("fs");
const toml = require("toml");
const hhConfig = require("hardhat/config");
const tasks = require("hardhat/builtin-tasks/task-names");
const subtask = hhConfig.subtask;
const TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS = tasks.TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS;

let solcVersion = "^0.8.19";

try {
  const foundry = toml.parse(fs.readFileSync("./foundry.toml").toString());
  if (foundry.default["solc-version"]) {
    solcVersion = foundry.default["solc-version"];
  }
} catch (e) {}

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, __, runSuper) => {
  const paths = await runSuper();
  return paths.filter((path) => !path.endsWith(".t.sol"));
});

const PRIVATE_KEY = "";
const ETHERSCAN_KEY = "";

const hhConf = {
  paths: {
    cache: "hh-cache",
    sources: "src",
    tests: "test",
  },
  solidity: {
    version: solcVersion,
    settings: {
      optimizer: {
        enabled: true,
        runs: 10000000,
      },
    },
  },
  networks: {
    localhost: {
      url: `http://127.0.0.1:8545/`,
    },
    arbitrumSepolia: {
      url: "https://sepolia-rollup.arbitrum.io/rpc",
    },
    arbitrumOne: {
      url: `https://arb1.arbitrum.io/rpc`,
    },
  },
};

if (PRIVATE_KEY) {
  hhConf.networks.localhost = {
    accounts: [PRIVATE_KEY],
  };
  hhConf.networks.arbitrumSepolia.accounts = [PRIVATE_KEY];
}

if (ETHERSCAN_KEY) {
  hhConf.etherscan = {
    apiKey: {
      arbitrumOne: ETHERSCAN_KEY,
      arbitrumSepolia: ETHERSCAN_KEY,
    },
    customChains: [
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io",
        },
      },
    ],
  };
}
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = hhConf;
