import { http, custom, createPublicClient } from 'viem'
import { arbitrum, base, mainnet } from 'viem/chains'

export function hello() {
  return 'Hello, world!';
}

export function createPublicClientForChain(chainId) {
  let chain;
  switch (chainId) {
    case "0x1":
      chain = mainnet
      break;
    case "0xa4b1":
      chain = arbitrum
      break;
    case "0x2105":
      chain = base
      break;
    default: throw new Error(`Unsupported chain ID: ${chainId}`)
  }

  // TODO: maybe instead of just returning the client, we could add an `http()` with a eip6963 event?
  return createPublicClient({
    chain,
    transport: http()
  });
};

export function createWalletClientForChain(chainId, eip1193Provider) {
  let chain;
  switch (chainId) {
    case "0xa4b1":
      chain = arbitrum
      break;
    default: throw new Error(`Unsupported chain ID: ${chainId}`)
  }

  return createWalletClient({
    chain,
    transport: custom(eip1193Provider)
  });
};
