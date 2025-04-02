# Espresso-Arbitrum Rollup Integration

![Espresso Network](https://img.shields.io/badge/Espresso-Network-blue)
![Arbitrum Nitro](https://img.shields.io/badge/Arbitrum-Nitro-purple)
![Chain ID](https://img.shields.io/badge/Chain_ID-898989-orange)

## Overview

This project demonstrates a fully functional rollup deployment integrated with Espresso's Decaf testnet and Arbitrum Sepolia. Our implementation leverages Espresso's fast confirmations to create a specialized L2 solution that provides enhanced security guarantees through Byzantine Fault Tolerance (BFT) consensus while maintaining the speed advantages of a traditional rollup architecture.

## Key Features

* 🚀 Fully functional rollup deployed on Espresso's Decaf testnet
* ⚡ Integrated with Espresso confirmations for enhanced security and speed
* 🔄 Seamless compatibility with Arbitrum Sepolia
* 🔒 TEE-backed batch poster for improved trust assumptions
* ⏱️ Faster confirmations than traditional Ethereum finality

## Deployment Information

**CreateRollup Transaction Hash**: `0xf33d16d9449ab9624d3727726afe9f37414381cabf00fe3836101b3f3de6f176`  
**Cloud Server IP Address**: `3.27.107.202`  
**Chain ID / Namespace**: `898989`

## Technical Architecture

Our rollup implementation consists of the following components:

1. **Sequencer Node**: Responsible for transaction ordering and batch creation
2. **Prover Service**: Generates validity proofs for transaction batches
3. **Espresso Integration Layer**: Connects to Decaf testnet for fast confirmations
4. **Arbitrum Bridge**: Enables cross-chain communication with Arbitrum Sepolia

## How It Works

The integration between our rollup and the Espresso Network provides several advantages over traditional rollup architectures:

1. A user transacts on our Arbitrum-based chain
2. The transaction is processed by our sequencer, providing a soft-confirmation
3. Simultaneously, transactions are sent to the Espresso Network for stronger BFT consensus-backed confirmations
4. Our batch poster, operating in a Trusted Execution Environment (TEE), honors the Espresso Network confirmation
5. The batch is ultimately submitted to the base layer (Arbitrum Sepolia)

This architecture provides stronger guarantees that transactions will be included and finalized correctly, reducing the trust requirements in the sequencer.

## Getting Started

### Prerequisites

- Node.js 16+
- Yarn
- Foundry
- Git
- Build-essential tools

### Deployment Steps

1. Clone the contracts repository:
```bash
git clone https://github.com/EspressoSystems/nitro-contracts.git
cd nitro-contracts
git checkout develop
```

2. Install dependencies:
```bash
yarn install && forge install
yarn build:all
```

3. Configure environment:
Create a `.env` file with:
```
ARBISCAN_API_KEY="YOUR_KEY_HERE"
DEVNET_PRIVKEY="YOUR_PRIVATE_KEY"
ESPRESSO_TEE_VERIFIER_ADDRESS="0x8354db765810dF8F24f1477B06e91E5b17a408bF"
```

4. Configure deployment:
Modify `config.ts` with your chain settings:
```typescript
owner: "OWNER_ADDRESS",
chainId: ethers.BigNumber.from('898989'),
chainConfig: {
    "chainId": 898989,
    "InitialChainOwner": "YOUR_OWNED_ADDRESS",
}
validators: ["AN_OWNED_ADDRESS"],
batchPosterAddress: ["ANOTHER_OWNED_ADDRESS"],
batchPosterManager: "ANOTHER_OWNED_ADDRESS",
```

5. Run deployment scripts:
```bash
npx hardhat run scripts/deployment.ts --network arbSepolia
# Add ROLLUP_CREATOR_ADDRESS to .env
npx hardhat run scripts/createEthRollup.ts --network arbSepolia
```

## Use Cases

Our rollup solution is particularly well-suited for:

- Applications requiring faster confirmation times than base Ethereum
- Use cases where sequencer trust minimization is critical
- DeFi protocols that can benefit from BFT consensus guarantees
- Cross-chain applications that need reliable state verification

## Future Improvements

- Implement full TEE verification for the batch poster
- Add support for deployment on Arbitrum One mainnet
- Enhance cross-chain messaging capabilities
- Optimize gas costs for batch submissions

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Espresso Systems for their confirmation layer technology
- Arbitrum team for the Nitro rollup stack
- Hackathon organizers and mentors
