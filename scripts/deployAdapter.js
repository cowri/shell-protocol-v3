const hre = require("hardhat");
const fs = require("fs")
const path = require("path")

const deployProteusAdapter = async (signer, ocean, primitiveAddress, xTokenAddress, yTokenAddress) => {
    const adapterContract = await hre.ethers.getContractFactory('ProteusAdapter', signer)
    const adapter = await adapterContract.deploy(ocean, primitiveAddress, xTokenAddress, yTokenAddress)

    await adapter.deployed();

    console.log("Adapter address", adapter.address)
    
    await hre.run("verify:verify", {
        address: adapter.address,
        constructorArguments: [ocean, primitiveAddress, xTokenAddress, yTokenAddress],
    })

    return adapter.address
}

const deployAdapter = async (signer, ocean, primitiveName, primitiveAddress) => {
    const adapterContract = await hre.ethers.getContractFactory(primitiveName, signer)
    const adapter = await adapterContract.deploy(ocean, primitiveAddress)

    await adapter.deployed();

    console.log("Adapter address", adapter.address)
    
    await hre.run("verify:verify", {
        address: adapter.address,
        constructorArguments: [ocean, primitiveAddress],
    })

    return adapter.address
}

const deployBalancerStablePoolAdapter = async (signer, oceanAddress) => {
  const adapterContract = await hre.ethers.getContractFactory("BalancerAdapter", signer);

  const vault = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";

  const tokenOne = "0x5979D7b546E38E414F7E9822514be443A4800529";
  const tokenTwo = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  const tokenOneIndex = 0;
  const tokenTwoIndex = 1;
  const poolId = "0x9791d590788598535278552eecd4b211bfc790cb000000000000000000000498";

  const adapter = await adapterContract.deploy(
    oceanAddress,
    vault,
    tokenOne,
    tokenTwo,
    tokenOneIndex,
    tokenTwoIndex,
    poolId,
  );

  await adapter.deployed();

  console.log("Adapter address", adapter.address);

  await hre.run("verify:verify", {
    address: adapter.address,
    constructorArguments: [oceanAddress, vault, tokenOne, tokenTwo, tokenOneIndex, tokenTwoIndex, poolId],
  });

  return adapter.address;
};

const deployPoolQuery = async (signer, queryName, adapter, statelessPool) => {
    const queryContract = await hre.ethers.getContractFactory(queryName, signer)
    const query = await queryContract.deploy(adapter, statelessPool)

    await query.deployed()

    console.log("Query address", query.address)
    
    await hre.run("verify:verify", {
        address: query.address,
        constructorArguments: [adapter, statelessPool],
    })    
}

async function main() {

    const signer = await ethers.getSigner();

    console.log('Deploying from', signer.address)
    console.log('Deployer ETH balance', ethers.utils.formatEther(await ethers.provider.getBalance(signer.address)))

    const oceanAddress = '0x96B4f4E401cCD70Ec850C1CF8b405Ad58FD5fB7a'

    const adapter = await deployBalancerStablePoolAdapter(signer, oceanAddress)

    await deployPoolQuery(signer, 'BalancerVolatilePoolQuery', adapter.address, 'INSERT_STATELESS_POOL')
    
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});