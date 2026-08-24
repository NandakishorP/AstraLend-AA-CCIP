import { ethers } from "ethers";
import { CHAIN_CONFIGS, env, type ChainKey } from "../config/env.js";
import { getProvider } from "../blockchain/providers.js";
import { getLendingPoolRead } from "../blockchain/contracts.js";
import { getResolvedTokens } from "../services/token.service.js";
import { ccipRepo, eventRepo, indexerRepo, type NewEvent } from "../db/repositories.js";
import { decodeCcipSend, decodeProtocolLog } from "./decode.js";

/**
 * Chain indexer.
 *
 * Follows each configured chain, decodes protocol logs and cross-chain sends,
 * and persists them. The API then answers history questions from the database
 * instead of re-scanning the chain on every request — the difference between a
 * multi-second `eth_getLogs` sweep and a keyed index lookup.
 *
 * Deliberately a plain polling loop rather than a subscription: local nodes drop
 * installed filters when state is reverted, and a silently dead subscription is
 * far worse than a two-second delay.
 */

interface ChainIndexer {
  chain: ChainKey;
  timer: NodeJS.Timeout | null;
  running: boolean;
  stopped: boolean;
}

const indexers = new Map<ChainKey, ChainIndexer>();

/** Depth to rewind when the chain disagrees with what we recorded. */
const REORG_REWIND_BLOCKS = 12;

/**
 * On a fresh database, how far back to look on a chain that already has deep
 * history. Local nodes start at genesis; a public testnet would take hours to
 * sweep from block 0 for a contract deployed last week.
 */
const MAX_COLD_START_BLOCKS = 200_000;

export function startIndexer(logger: {
  info: (msg: string) => void;
  warn: (msg: string) => void;
  error: (msg: string) => void;
}): void {
  if (!env.INDEXER_ENABLED) {
    logger.info("indexer disabled (INDEXER_ENABLED=false)");
    return;
  }

  for (const chain of Object.keys(CHAIN_CONFIGS) as ChainKey[]) {
    if (!CHAIN_CONFIGS[chain].lendingPool) continue;

    const state: ChainIndexer = { chain, timer: null, running: false, stopped: false };
    indexers.set(chain, state);

    const tick = async () => {
      if (state.stopped || state.running) return;
      state.running = true;
      try {
        await indexChain(chain);
      } catch (error) {
        const message = (error as Error).message;
        indexerRepo.recordError(chain, message);
        logger.warn(`indexer[${chain}] ${message}`);
      } finally {
        state.running = false;
      }
    };

    void tick();
    state.timer = setInterval(() => void tick(), env.INDEXER_POLL_MS);
    logger.info(`indexer[${chain}] started, polling every ${env.INDEXER_POLL_MS}ms`);
  }
}

export function stopIndexer(): void {
  for (const state of indexers.values()) {
    state.stopped = true;
    if (state.timer) clearInterval(state.timer);
  }
  indexers.clear();
}

/**
 * Indexes one pass for a chain: detect reorgs, then walk forward in batches
 * until caught up with the head.
 */
async function indexChain(chain: ChainKey): Promise<void> {
  const provider = getProvider(chain);
  const head = await provider.getBlockNumber();

  let state = indexerRepo.get(chain);
  if (!state) {
    const start = Math.max(0, head - MAX_COLD_START_BLOCKS);
    indexerRepo.init(chain, start);
    state = indexerRepo.get(chain)!;
  }

  // A head below our cursor means the chain was rewound underneath us — a local
  // snapshot revert, or a fresh node on the same port. Re-index from there.
  if (head < state.lastBlock) {
    indexerRepo.rollback(chain, head);
    state = indexerRepo.get(chain)!;
  }

  // Reorg check: the block we last indexed should still hash the same.
  if (state.lastBlockHash && state.lastBlock > 0) {
    const block = await provider.getBlock(state.lastBlock).catch(() => null);
    if (!block || block.hash !== state.lastBlockHash) {
      const rewindTo = Math.max(state.startBlock, state.lastBlock - REORG_REWIND_BLOCKS);
      indexerRepo.rollback(chain, rewindTo);
      state = indexerRepo.get(chain)!;
    }
  }

  if (state.lastBlock >= head) return;

  // Walk forward in bounded windows so a cold start cannot issue one enormous
  // getLogs that the provider rejects.
  let cursor = state.lastBlock;
  while (cursor < head) {
    const from = cursor + 1;
    const to = Math.min(head, cursor + env.INDEXER_BATCH_BLOCKS);

    const inserted = await indexRange(chain, from, to);
    const tipHash = to === head ? ((await provider.getBlock(to))?.hash ?? null) : null;
    indexerRepo.advance(chain, to, tipHash, inserted);

    cursor = to;
  }
}

/**
 * Every contract whose logs the indexer watches, discovered from the pool.
 *
 * Protocol events are emitted by the controllers rather than the pool itself —
 * the pool delegates each action, so `LiquidityDeposited` comes from the
 * LiquidityController's address, not the proxy's. Liquidations come from the
 * GSM. Asking the pool for those addresses keeps the indexer correct against any
 * deployment without a second source of configuration to keep in sync.
 *
 * Cached for the process lifetime: these are set once at deployment.
 */
const watchedAddresses = new Map<ChainKey, string[]>();

async function getWatchedAddresses(chain: ChainKey): Promise<string[]> {
  const cached = watchedAddresses.get(chain);
  if (cached) return cached;

  const config = CHAIN_CONFIGS[chain];
  const addresses = new Set<string>();

  if (config.lendingPool) addresses.add(config.lendingPool.toLowerCase());
  if (config.ccipRouter) addresses.add(config.ccipRouter.toLowerCase());

  if (config.lendingPool) {
    const pool = getLendingPoolRead(chain);
    const discovered = await Promise.all([
      pool.getLiquidityControllerAddress().catch(() => null),
      pool.getCollateralControllerAddress().catch(() => null),
      pool.getLoanControllerAddress().catch(() => null),
      // The satellite chain has no GSM, so this legitimately returns zero there.
      pool.getGSMAddress().catch(() => null),
    ]);

    for (const address of discovered) {
      if (address && address !== ethers.ZeroAddress) addresses.add(String(address).toLowerCase());
    }
  }

  const list = [...addresses];
  // Only cache once the controllers actually resolved, so a call made while the
  // node was still starting does not pin an incomplete list for the whole run.
  if (list.length > 2) watchedAddresses.set(chain, list);
  return list;
}

/** Fetches, decodes and persists every relevant log in a block range. */
async function indexRange(chain: ChainKey, fromBlock: number, toBlock: number): Promise<number> {
  const config = CHAIN_CONFIGS[chain];
  const provider = getProvider(chain);

  const addresses = await getWatchedAddresses(chain);
  if (addresses.length === 0) return 0;

  // One request per watched contract. `getLogs` accepts an address array on most
  // providers, but not all, and two small queries beat one rejected one.
  const logGroups = await Promise.all(
    addresses.map((address) => provider.getLogs({ address, fromBlock, toBlock }))
  );
  const logs = logGroups.flat();
  if (logs.length === 0) return 0;

  // Block timestamps: fetch once per distinct block, not once per log.
  const blockNumbers = [...new Set(logs.map((log) => log.blockNumber))];
  const timestamps = new Map<number, number>();
  await Promise.all(
    blockNumbers.map(async (number) => {
      const block = await provider.getBlock(number).catch(() => null);
      if (block) timestamps.set(number, block.timestamp);
    })
  );

  const tokens = await getResolvedTokens(chain).catch(() => []);
  const tokenMeta = new Map(
    tokens.map((token) => [token.address.toLowerCase(), token])
  );

  const events: NewEvent[] = [];
  const routerAddress = config.ccipRouter?.toLowerCase();

  for (const log of logs) {
    const timestamp = timestamps.get(log.blockNumber) ?? Math.floor(Date.now() / 1000);

    // Cross-chain sends come from the router, protocol events from the pool.
    if (routerAddress && log.address.toLowerCase() === routerAddress) {
      recordCcipSend(chain, log, timestamp);
      continue;
    }

    const decoded = decodeProtocolLog(log);
    if (!decoded) continue;

    const meta = decoded.tokenAddress ? tokenMeta.get(decoded.tokenAddress.toLowerCase()) : undefined;

    events.push({
      chain,
      blockNumber: log.blockNumber,
      blockHash: log.blockHash,
      txHash: log.transactionHash,
      logIndex: log.index,
      timestamp,
      eventName: decoded.eventName,
      kind: decoded.kind,
      userAddress: decoded.userAddress,
      tokenAddress: decoded.tokenAddress,
      tokenSymbol: meta?.symbol ?? null,
      tokenDecimals: meta?.decimals ?? null,
      amount: decoded.amount,
      args: decoded.args,
    });
  }

  return eventRepo.insertMany(events);
}

/** Persists a cross-chain send so the UI can show it as in flight. */
function recordCcipSend(chain: ChainKey, log: ethers.Log, timestamp: number): void {
  const decoded = decodeCcipSend(log);
  if (!decoded) return;

  const destChain =
    (Object.keys(CHAIN_CONFIGS) as ChainKey[]).find(
      (key) => CHAIN_CONFIGS[key].chainSelector === decoded.destinationChainSelector
    ) ?? null;

  ccipRepo.recordSent({
    messageId: decoded.messageId,
    sourceChain: chain,
    destChain,
    destSelector: decoded.destinationChainSelector,
    sender: decoded.sender,
    receiver: decoded.receiver,
    userAddress: decoded.userAddress,
    action: decoded.action,
    feePaid: decoded.feePaid,
    sentTx: log.transactionHash,
    sentBlock: log.blockNumber,
    sentAt: timestamp,
  });
}

/** Current indexer health, per chain — surfaced at GET /indexer/status. */
export async function getIndexerStatus(): Promise<
  {
    chain: ChainKey;
    enabled: boolean;
    lastBlock: number;
    headBlock: number | null;
    blocksBehind: number | null;
    eventsIndexed: number;
    reorgsHandled: number;
    lastRunAt: number | null;
    lastError: string | null;
  }[]
> {
  const chains = (Object.keys(CHAIN_CONFIGS) as ChainKey[]).filter(
    (chain) => CHAIN_CONFIGS[chain].lendingPool
  );

  return Promise.all(
    chains.map(async (chain) => {
      const state = indexerRepo.get(chain);
      const head = await getProvider(chain)
        .getBlockNumber()
        .catch(() => null);

      return {
        chain,
        enabled: env.INDEXER_ENABLED,
        lastBlock: state?.lastBlock ?? 0,
        headBlock: head,
        blocksBehind: head !== null && state ? Math.max(0, head - state.lastBlock) : null,
        eventsIndexed: state?.eventsIndexed ?? 0,
        reorgsHandled: state?.reorgsHandled ?? 0,
        lastRunAt: state?.lastRunAt ?? null,
        lastError: state?.lastError ?? null,
      };
    })
  );
}
