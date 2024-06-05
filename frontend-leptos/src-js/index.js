import { http, custom, createPublicClient, createWalletClient } from 'viem'
import { arbitrum, base, mainnet } from 'viem/chains'

export function hello() {
  return 'Hello, world!';
}

function chainIdToChain(chainId) {
  switch (chainId) {
    case "0x1":
      return mainnet;
    case "0xa4b1":
      return arbitrum;
    case "0x2105":
      return base;
    default: throw new Error(`Unsupported chain ID: ${chainId}`)
  }
}

export function createPublicClientForChain(chainId) {
  return createPublicClient({
    chain: chainIdToChain(chainId),
    transport: http()
  });
};

export function createWalletClientForChain(chainId, eip1193Provider) {
  return createWalletClient({
    chain: chainIdToChain(chainId),
    transport: custom(eip1193Provider)
  });
};
