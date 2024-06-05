import { http, custom, createPublicClient, createWalletClient, fallback } from 'viem'
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

export function createPublicClientForChain(chainId, eip1193_provider) {
  let transport;
  if (eip1193_provider === undefined) {
    transport = http();
  } else {
    // TODO: with a fallback to http
    transport = fallback([
      custom(eip1193_provider),
      http(),
    ]);
  }

  const publicClient = createPublicClient({
    batch: {
      multicall: true,
    },
    chain: chainIdToChain(chainId),
    transport
  });

  // globalThis.window.publicClient = publicClient;

  return publicClient;
};

export function createWalletClientForChain(chainId, eip1193Provider) {
  const walletClient = createWalletClient({
    chain: chainIdToChain(chainId),
    transport: custom(eip1193Provider)
  });

  // globalThis.window.walletClient = walletClient;

  return walletClient;
};
