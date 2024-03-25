# Shell v3
Shell v3 improves upon the fundamentals developed in Shell v2, which you can learn more about [here](https://wiki.shellprotocol.io/how-shell-works/the-ocean-accounting-hub) & [here](https://github.com/Shell-Protocol/Shell-Protocol#the-ocean), we highly recommmend to go through these resources before diving into the v3 improvements.

We also recommend devs to dive into [adapter integration docs](https://wiki.shellprotocol.io/getting-started/developers/what-to-build-on-shell#connect-external-protocols-with-shell)

The goal of Shell v3 is to make the Ocean compatible with external protocols through the use of adapter primitives.

## V3 Updates
### The Ocean
- Removed reentrancy guards for `doInteraction` and `doMultipleInteraction` methods so that adapter primitives may wrap/unwrap tokens to be used with external protocols.

- `doInteraction` has been updated to enable wrapping Ether.

- Refactored the order in which a primitive's balances are updated. Previously, both mints and burns would occur after the primitive had performed its computation in `computeOutputAmount` or `computeInputAmount`. Now, the primitive's balances will be minted the input token or burned the output token before performing the computation step, and then will burn the output token or mint the input token based on the result.


### Adapter Primitives
- Introducing [OceanAdapter.sol](https://github.com/cowri/shell-protocol-v3-contracts/blob/main/src/adapters/OceanAdapter.sol), a generalized adapter interface for adapter primitives.
- Demonstrated implementation in [examples](https://github.com/cowri/shell-protocol-v3/tree/main/src/adapters) 

## Security

Currently, we use [Slither](https://github.com/crytic/slither) to help identify well-known issues via static analysis. Other tools may be added in the near future as part of the continuous improvement process.

### Static Analysis

To run the analysis
```shell
slither . --foundry-compile-all

```

### Installation

Run `git clone https://github.com/cowri/shell-protocol-v3-contracts.git` & then run `yarn install`

### Testing
Foundry mainnet fork tests powered by fuzzing for the existing different adapters are located [here](https://github.com/cowri/shell-protocol-v3-contracts/tree/main/src/test/fork) for reference

To compile the contracts
```shell
forge build
```

To run Foundry tests
```shell
forge test
```

To run coverage for Foundry tests
```shell
forge coverage
```

For coverage for the **Adapter Contracts** run `forge coverage`
