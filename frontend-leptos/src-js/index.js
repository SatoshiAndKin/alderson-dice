import { createPublicClient, webSocket, http } from 'viem'
import { arbitrum } from 'viem/chains'

export function createPublicArbitrumClient() {
  return createPublicClient({
    chain: arbitrum,
    transport: http(),
  });
}

export { createPublicClient, webSocket, http, arbitrum };
