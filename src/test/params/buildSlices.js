function generateSolidityContract(numSlices) {
  if (numSlices < 2) {
    throw new Error("Number of slices must be at least 2.");
  }

  let solidityCode = `// SPDX-License-Identifier: MIT
// Cowri Labs Inc.
  
pragma solidity ^0.8.10;

contract Slices {
  uint256 constant NUMBER_OF_SLICES = ${numSlices};
  uint256 constant NUMBER_OF_SLOPES = NUMBER_OF_SLICES - 1;\n`;

  for (let i = 0; i < numSlices - 1; i++) {
    solidityCode += `
  int128 immutable m${i};`;
  }

  solidityCode += '\n';

  for (let i = 0; i < numSlices; i++) {
    solidityCode += `
  int128 immutable a${i};`;
  }

  solidityCode += '\n';

  for (let i = 0; i < numSlices; i++) {
    solidityCode += `
  int128 immutable b${i};`;
  }

  solidityCode += '\n';

  for (let i = 0; i < numSlices; i++) {
    solidityCode += `
  int128 immutable k${i};`;
  }

  solidityCode += `
      
  constructor(
      int128[] memory ms,
      int128[] memory _as,
      int128[] memory bs,
      int128[] memory ks
  ) {
  
    require(ms.length == NUMBER_OF_SLOPES);
    require(_as.length == NUMBER_OF_SLICES);
    require(bs.length == NUMBER_OF_SLICES);
    require(ks.length == NUMBER_OF_SLICES);\n`;

  for (let i = 0; i < numSlices - 1; i++) {
    solidityCode += `
    m${i} = ms[${i}];`;
  }

  solidityCode += '\n';

  for (let i = 0; i < numSlices; i++) {
    solidityCode += `
    a${i} = _as[${i}];`;
  }

  solidityCode += '\n';

  for (let i = 0; i < numSlices; i++) {
    solidityCode += `
    b${i} = bs[${i}];`;
  }

  solidityCode += '\n';

  for (let i = 0; i < numSlices; i++) {
    solidityCode += `
    k${i} = ks[${i}];`;
  }

  solidityCode += `

  }
  
  function getSlopes() public view returns (int128[] memory slopes) {
      slopes = new int128[](NUMBER_OF_SLOPES);`;

  for (let i = 0; i < numSlices - 1; i++) {
    solidityCode += `
      slopes[${i}] = m${i};`;
  }

  solidityCode += `
  }
  
  function getAs() public view returns (int128[] memory _as) {
      _as = new int128[](NUMBER_OF_SLICES);`;

  for (let i = 0; i < numSlices; i++) {
    solidityCode += `
      _as[${i}] = a${i};`;
  }

  solidityCode += `
  }
  
  function getBs() public view returns (int128[] memory bs) {
      bs = new int128[](NUMBER_OF_SLICES);`;

  for (let i = 0; i < numSlices; i++) {
    solidityCode += `
      bs[${i}] = b${i};`;
  }

  solidityCode += `
  }
  
  function getKs() public view returns (int128[] memory ks) {
      ks = new int128[](NUMBER_OF_SLICES);`;

  for (let i = 0; i < numSlices; i++) {
    solidityCode += `
      ks[${i}] = k${i};`;
  }

  solidityCode += `
  }
}`;

  return solidityCode;
}

module.exports = { generateSolidityContract }
