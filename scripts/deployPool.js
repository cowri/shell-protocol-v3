const { ethers } = require("hardhat");
const hre = require("hardhat");
const shellv2 = require("../utils-js");
const { calculateWrappedTokenId } = require("../utils-js/utils");

const deployERC20 = async (signer, initial, decimals) => {
  const ERC20Contract = await ethers.getContractFactory("ERC20MintsToDeployer", signer);

  const token = await ERC20Contract.deploy(initial, decimals);
  await token.deployed();
  return token.address;
};

const deployERC721 = async (signer, amount) => {
  const ERC721Contract = await ethers.getContractFactory("ERC721MintsToDeployer", signer);

  const ids = [...Array(amount).keys()];

  const token = await ERC721Contract.deploy(ids);
  await token.deployed();

  await hre.run("verify:verify", {
    address: token.address,
    constructorArguments: [ids],
    contract: "src/mock/ERC721MintsToDeployer.sol:ERC721MintsToDeployer",
  });

  return token.address;
};

const ONE = BigInt(1e18);
const ABDK_ONE = BigInt(2) ** BigInt(64);

const formatParam = (param) => {
  return (BigInt(Math.floor(param * 1e18)) * ABDK_ONE) / ONE;
};

const deployProteus = async (signer, ocean, tokens, ms, _as, bs, ks, feePercent, initialLPSupply) => {
  ms = ms.map((m) => formatParam(m));
  _as = _as.map((a) => formatParam(a));
  bs = bs.map((b) => formatParam(b));
  ks = ks.map((k) => formatParam(k));

  const fee = 200 / feePercent;

  const init = [];

  for (let i = 0; i < tokens.length; i++) {
    if (!tokens[i].wrapped && tokens[i].address !== "Ether") {
      const tokenContract = await hre.ethers.getContractAt("ERC20", tokens[i].address);
      await tokenContract.connect(signer).approve(ocean.address, tokens[i].intialDeposit);
      init.push(shellv2.interactions.wrapERC20({ address: tokens[i].address, amount: tokens[i].intialDeposit }));
    } else if (tokens[i].address == "Ether") {
      // Wrap ETH into the Ocean
      await ocean.connect(signer).doMultipleInteractions([], [tokens[i].oceanID], { value: tokens[i].intialDeposit });
    }
  }

  console.log("Approved tokens");

  const proxyContract = await ethers.getContractFactory("LiquidityPoolProxy", signer);
  const proteusContract = await ethers.getContractFactory("Proteus", signer);

  const proxy = await proxyContract.deploy(tokens[0].oceanID, tokens[1].oceanID, ocean.address, initialLPSupply);

  await proxy.deployed();

  const proteus = await proteusContract.deploy(ms, _as, bs, ks, fee);

  await proteus.deployed();

  await proxy.connect(signer).setImplementation(proteus.address);

  console.log("Deployed liquidity pool proxy and implementation");

  const lpTokenId = await proxy.lpTokenId();

  tokens.forEach((token) => {
    init.push(
      shellv2.interactions.computeOutputAmount({
        address: proxy.address,
        inputToken: token.oceanID,
        outputToken: lpTokenId,
        specifiedAmount: token.intialDeposit,
        metadata: shellv2.constants.THIRTY_TWO_BYTES_OF_ZERO,
      }),
    );
  });

  await shellv2.executeInteractions({
    ocean,
    signer,
    interactions: init,
  });

  console.log("Seeded pool with initial liquidity");
  console.log("Pool contract address:", proxy.address);
  console.log("LP token ID:", lpTokenId.toHexString());

  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    console.log(
      token.address,
      ethers.utils.formatUnits(await ocean.connect(signer).balanceOf(proxy.address, token.oceanID)),
    );
  }

  console.log("LP Supply", ethers.utils.formatUnits(await ocean.connect(signer).balanceOf(signer.address, lpTokenId)));

  try {
    await hre.run("verify:verify", {
      address: proxy.address,
      constructorArguments: [tokens[0].oceanID, tokens[1].oceanID, ocean.address, initialLPSupply],
    });
  } catch {}

  try {
    await hre.run("verify:verify", {
      address: proteus.address,
      constructorArguments: [ms, _as, bs, ks, fee],
    });
  } catch {}
};

const deployEvolvingProteus = async (
  signer,
  ocean,
  tokens,
  proxyAddress,
  pyInit,
  pxInit,
  pyFinal,
  pxFinal,
  startTime,
  duration,
  feePercent,
  initialLPSupply,
) => {
  pyInit = formatParam(pyInit);
  pxInit = formatParam(pxInit);
  pyFinal = formatParam(pyFinal);
  pxFinal = formatParam(pxFinal);

  if (startTime == 0) {
    startTime = Math.floor(Date.now() / 1000);
    console.log(startTime);
  }

  const fee = 200 / feePercent;

  let proxy;
  if (proxyAddress) {
    proxy = await hre.ethers.getContractAt("LiquidityPoolProxy", proxyAddress);

    const proteusContract = await ethers.getContractFactory("EvolvingProteus", signer);

    const proteus = await proteusContract.deploy(pyInit, pxInit, pyFinal, pxFinal, startTime, duration, fee);
    await proteus.deployed();
    await proxy.connect(signer).setImplementation(proteus.address);

    console.log("New implementation contract:", await proxy.implementation());

    await getEvolvingParams(signer, proxyAddress);

    try {
      await hre.run("verify:verify", {
        address: proteus.address,
        constructorArguments: [pyInit, pxInit, pyFinal, pxFinal, startTime, duration, fee],
      });
    } catch {}
  } else {
    const init = [];

    for (let i = 0; i < tokens.length; i++) {
      if (!tokens[i].wrapped && tokens[i].address !== "Ether") {
        const tokenContract = await hre.ethers.getContractAt("ERC20", tokens[i].address);
        await tokenContract.connect(signer).approve(ocean.address, tokens[i].intialDeposit);
        init.push(shellv2.interactions.wrapERC20({ address: tokens[i].address, amount: tokens[i].intialDeposit }));
      } else if (tokens[i].address == "Ether") {
        // Wrap ETH into the Ocean
        await ocean.connect(signer).doMultipleInteractions([], [tokens[i].oceanID], { value: tokens[i].intialDeposit });
      }
    }

    console.log("Approved tokens");

    const proxyContract = await ethers.getContractFactory("LiquidityPoolProxy", signer);

    proxy = await proxyContract.deploy(tokens[0].oceanID, tokens[1].oceanID, ocean.address, initialLPSupply);
    await proxy.deployed();
    const proteusContract = await ethers.getContractFactory("EvolvingProteus", signer);

    const proteus = await proteusContract.deploy(pyInit, pxInit, pyFinal, pxFinal, startTime, duration, fee);
    await proteus.deployed();
    await proxy.connect(signer).setImplementation(proteus.address);

    console.log("New implementation contract:", await proxy.implementation());

    console.log("Deployed liquidity pool proxy and implementation");

    const lpTokenId = await proxy.lpTokenId();
    tokens.forEach((token) => {
      init.push(
        shellv2.interactions.computeOutputAmount({
          address: proxy.address,
          inputToken: token.oceanID,
          outputToken: lpTokenId,
          specifiedAmount: token.intialDeposit,
          metadata: shellv2.constants.THIRTY_TWO_BYTES_OF_ZERO,
        }),
      );
    });

    await shellv2.executeInteractions({
      ocean,
      signer,
      interactions: init,
    });

    console.log("Seeded pool with initial liquidity");
    console.log("Pool contract address:", proxy.address);
    console.log("LP token ID:", lpTokenId.toHexString());

    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      console.log(
        token.address,
        ethers.utils.formatUnits(await ocean.connect(signer).balanceOf(proxy.address, token.oceanID)),
      );
    }

    console.log(
      "LP Supply",
      ethers.utils.formatUnits(await ocean.connect(signer).balanceOf(signer.address, lpTokenId)),
    );

    try {
      await hre.run("verify:verify", {
        address: proxy.address,
        constructorArguments: [tokens[0].oceanID, tokens[1].oceanID, ocean.address, initialLPSupply],
      });
    } catch {}

    try {
      await hre.run("verify:verify", {
        address: proteus.address,
        constructorArguments: [pyInit, pxInit, pyFinal, pxFinal, startTime, duration, fee],
      });
    } catch {}
  }
};

const changeParams = async (signer, proxyAddress, ms, _as, bs, ks) => {
  const proteusContract = await ethers.getContractFactory("Proteus", signer);

  const proteus = await proteusContract.deploy(ms, _as, bs, ks);
  await proteus.deployed();
  const proxy = await hre.ethers.getContractAt("LiquidityPoolProxy", proxyAddress);

  await proxy.connect(signer).setImplementation(proteus.address);

  console.log("New implementation contract:", proteus.address);

  await hre.run("verify:verify", {
    address: proteus.address,
    constructorArguments: [ms, _as, bs, ks],
  });
};

const updateImp = async (signer, proxyAddress, impAddress) => {
  const proxy = await hre.ethers.getContractAt("LiquidityPoolProxy", proxyAddress);

  await proxy.connect(signer).setImplementation(impAddress);

  console.log("New implementation contract:", await proxy.implementation());
};

const freezePool = async (signer, proxyAddress, freeze) => {
  const proxy = await hre.ethers.getContractAt("LiquidityPoolProxy", proxyAddress);
  await proxy.connect(signer).freezePool(freeze);

  console.log("Pool frozen", await proxy.poolFrozen());
};

const getParams = async (signer, proxyAddress) => {
  const proxy = await hre.ethers.getContractAt("LiquidityPoolProxy", proxyAddress);
  const proteusAddress = proxy.implementation();

  const pool = await hre.ethers.getContractAt("Proteus", proteusAddress);

  const ms = (await pool.connect(signer).getSlopes()).map((_m) => ethers.utils.formatUnits(_m.mul(ONE).div(ABDK_ONE)));
  const _as = (await pool.connect(signer).getAs()).map((_a) => ethers.utils.formatUnits(_a.mul(ONE).div(ABDK_ONE)));
  const bs = (await pool.connect(signer).getBs()).map((_b) => ethers.utils.formatUnits(_b.mul(ONE).div(ABDK_ONE)));
  const ks = (await pool.connect(signer).getKs()).map((_k) => ethers.utils.formatUnits(_k.mul(ONE).div(ABDK_ONE)));

  console.log("Params", ms, _as, bs, ks);

  console.log(`Fee: ${200 / (await pool.BASE_FEE())}%`);
};

const getEvolvingParams = async (signer, proxyAddress) => {
  const proxy = await hre.ethers.getContractAt("LiquidityPoolProxy", proxyAddress);
  const proteusAddress = proxy.implementation();

  const pool = await hre.ethers.getContractAt("EvolvingProteus", proteusAddress);

  const pyInit = ethers.utils.formatUnits((await pool.connect(signer).py_init()).mul(ONE).div(ABDK_ONE));
  const pxInit = ethers.utils.formatUnits((await pool.connect(signer).px_init()).mul(ONE).div(ABDK_ONE));
  const pyFinal = ethers.utils.formatUnits((await pool.connect(signer).py_final()).mul(ONE).div(ABDK_ONE));
  const pxFinal = ethers.utils.formatUnits((await pool.connect(signer).px_final()).mul(ONE).div(ABDK_ONE));

  const startTime = new Date((await pool.connect(signer).t_init()) * 1000);
  const endTime = new Date((await pool.connect(signer).t_final()) * 1000);

  console.log("Params", pyInit, pxInit, pyFinal, pxFinal, startTime, endTime);

  console.log(`Fee: ${200 / (await pool.BASE_FEE())}%`);
};

const getBalances = async (signer, ocean, proxyAddress) => {
  const proxy = await hre.ethers.getContractAt("LiquidityPoolProxy", proxyAddress);
  const xToken = await proxy.connect(signer).xToken();
  const yToken = await proxy.connect(signer).yToken();
  const lpToken = await proxy.connect(signer).lpTokenId();
  const totalSupply = await proxy.connect(signer).getTokenSupply(lpToken);
  const balances = await ocean.connect(signer).balanceOfBatch([proxyAddress, proxyAddress], [xToken, yToken]);

  console.log(
    "Pool balances",
    balances.map((balance) => ethers.utils.formatUnits(balance)),
  );
  console.log("Total supply", ethers.utils.formatUnits(totalSupply));
};

async function main() {
  const signer = await ethers.getSigner();

  console.log("Deploying from", signer.address);
  console.log("Deployer ETH balance", ethers.utils.formatEther(await ethers.provider.getBalance(signer.address)));

  const ocean = await hre.ethers.getContractAt("Ocean", "0xe5Eb94CEaDEB1A87656b7FB57Cf22D01c1B3229d");

  const erc20Address = "";
  const wrappedEtherID = (await ocean.WRAPPED_ETHER_ID()).toHexString();

  const tokens = [
    {
      address: erc20Address,
      oceanID: calculateWrappedTokenId({ address: erc20Address, id: 0 }),
      wrapped: false,
      intialDeposit: hre.ethers.utils.parseEther("100"),
    },
    {
      address: "Ether",
      oceanID: wrappedEtherID,
      wrapped: false,
      intialDeposit: hre.ethers.utils.parseEther("0.1"),
    },
  ];

  const initialLPSupply = hre.ethers.utils.parseEther("100");

  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token.wrapped) {
      console.log(
        token.address,
        ethers.utils.formatUnits(await ocean.connect(signer).balanceOf(signer.address, token.oceanID)),
      );
    } else if (token.address !== "Ether") {
      const tokenContract = await hre.ethers.getContractAt("ERC20", token.address);
      console.log(token.address, token.oceanID, await tokenContract.connect(signer).balanceOf(signer.address));
    }
  }

  /* EDIT POOL DEPLOY PARAMETERS BELOW */

  let { ms, _as, bs, ks, feePercent } = require("../src/proteus/params/constant-product");

  await deployProteus(signer, ocean, tokens, ms, _as, bs, ks, feePercent, initialLPSupply);

}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
