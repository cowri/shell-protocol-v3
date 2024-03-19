const fs = require('fs');
const { generateSolidityContract } = require('./buildSlices');

let {ms, _as, bs, ks, feePercent} = require("../../proteus/params/constant-product");

const formatParams = (params) => {
  return params.map((value) => BigInt(value * 1e18).toString());
};
// Create an object with the desired JSON structure.
const params = {
  m: formatParams(ms),
  a: formatParams(_as),
  b: formatParams(bs),
  k: formatParams(ks),
  fee: 200 / feePercent
};

// Specify the JSON file path where you want to save the data.
const jsonFilePath = "./src/test/params/testParams.json";

// Write the data to the JSON file.
fs.writeFileSync(jsonFilePath, JSON.stringify(params, null, 2));

console.log(`Data written to ${jsonFilePath}`);

fs.readFile(jsonFilePath, "utf8", (err, data) => {
  if (err) {
    console.error(`Error reading file: ${err}`);
    return;
  }

  // Replace quotation marks from numerical strings
  const modifiedData = data.replace(/"(-?\d+\.\d*|\.\d+|-?\d+)"/g, "$1");

  fs.writeFile(jsonFilePath, modifiedData, "utf8", (err) => {
    if (err) {
      console.error(`Error writing file: ${err}`);
      return;
    }
    console.log(
      `Successfully removed quotes from numerical strings and saved to ${jsonFilePath}`
    );
  });
});

const numSlices = params.a.length
const solidityCode = generateSolidityContract(numSlices);
const solidityFilePath = './src/proteus/Slices.sol';

fs.writeFileSync(solidityFilePath, solidityCode);

console.log(`Solidity code for Slices written to ${solidityFilePath}`);