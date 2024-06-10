import { Chain, http, custom, createPublicClient, createWalletClient, fallback, getContract } from 'viem'
import { arbitrum, base, localhost, mainnet } from 'viem/chains'

import { abi as gameAbi } from "./AldersonDiceGameV1.json";
import { abi as nftAbi } from "./AldersonDiceNFT.json";

export function hello() {
  return 'Hello, world!';
}

function chainIdToChain(chainId): Chain {
  switch (chainId) {
    case "0x1":
      return mainnet;
    case "0x1337":
      return localhost;
    case "0x2105":
      // TODO: why isn't the type here happy?
      return base as Chain;
    case "0xa4b1":
      return arbitrum;
    default: throw new Error(`Unsupported chain ID: ${chainId}`)
  }
}

export function createPublicClientForChain(chainId, eip1193_provider) {
  // TODO: allow customizing this. dev we want 8545. prod we want undefined
  const fallbackUrl = "http://127.0.0.1:8545";

  let transport;
  if (eip1193_provider === undefined) {
    transport = http(fallbackUrl);
  } else {
    transport = fallback([
      custom(eip1193_provider),
      http(fallbackUrl),
    ]);
  }

  const publicClient = createPublicClient({
    batch: {
      multicall: true,
    },
    chain: chainIdToChain(chainId),
    transport
  });

  return publicClient;
};

export function createWalletClientForChain(chainId, eip1193Provider) {
  const walletClient = createWalletClient({
    chain: chainIdToChain(chainId),
    transport: custom(eip1193Provider)
  });

  return walletClient;
};

export function nftContract(publicClient, walletClient) {
  let client;

  if (walletClient === undefined) {
    client = publicClient;
  } else {
    client = {
      public: publicClient,
      wallet: walletClient,
    };
  }

  return getContract({
    // TODO: probably get this from build scripts in the rust pipeline
    address: '0xFFA4DB58Ad08525dFeB232858992047ECab26e95',
    abi: nftAbi,
    client,
  });
}

export function gameContract(publicClient, walletClient) {
  let client;

  if (walletClient === undefined) {
    client = publicClient;
  } else {
    client = {
      public: publicClient,
      wallet: walletClient,
    };
  }

  return getContract({
    // TODO: probably get this from build scripts in the rust pipeline
    address: '0xD77ce58aC199eA67CD2a86230e02FA679920828F',
    abi: gameAbi,
    client,
  });
}
