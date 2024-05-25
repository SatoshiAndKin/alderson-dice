import { createPublicClient, webSocket } from 'viem'
import { arbitrum } from 'viem/chains'

const publicClient = createPublicClient({
  chain: arbitrum,
  transport: webSocket(),
});

// TODO: create client that uses the user's wallet once they click connect

const blockNumber = await publicClient.getBlockNumber();

console.log("blockNumber", blockNumber);

window.aldersonDice = {
  publicClient,
  blockNumber,
};
