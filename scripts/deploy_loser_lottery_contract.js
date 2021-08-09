// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const config = require("./config.json");

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const network = "mumbai"; // Possible values : mumbai or matic
  const LoserLotteryContract = await hre.ethers.getContractFactory("LoserLotteryContract");
  // const loserLotteryContractInstance = await LoserLotteryContract.deploy(
  //   config[network].loserLotteryToken.distributionToken,
  //   config[network].loserLotteryToken.distributionAmount,
  //   config[network].loserLotteryToken.lotteryToken,
  // );

  // await loserLotteryContractInstance.deployed();

  // console.log("Loser Lottery Contract deployed to:", loserLotteryContractInstance.address);
  // await sleep(20000);

  await hre.run("verify:verify", {
    address: '0x17132127e21f3F409730a649BbE49238E67D7Fc1',
    constructorArguments: [
      config[network].loserLotteryToken.distributionToken,
      config[network].loserLotteryToken.distributionAmount,
      config[network].loserLotteryToken.lotteryToken,
    ],
  });

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
