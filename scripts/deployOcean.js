const hre = require("hardhat");

async function main() {
    const signer = await ethers.getSigner();

    console.log('Deploying from', signer.address)
    console.log('Deployer ETH balance', ethers.utils.formatEther(await ethers.provider.getBalance(signer.address)))

    const oceanContract = await ethers.getContractFactory("Ocean", signer);
    const ocean = await oceanContract.deploy("");
    await ocean.deployed();

    console.log('Deployed ocean')
    console.log('Ocean contract address:', ocean.address)

    await hre.run("verify:verify", {
        address: ocean.address,
        constructorArguments: [""],
    });
}

main()
    .then(() => process.exit(0))
    .catch((e) => {
        console.error(e);
        process.exit(1);
});