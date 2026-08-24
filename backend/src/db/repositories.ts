import { getDb, transaction } from "./index.js";
import type { ChainKey } from "../config/env.js";

/**
 * Every SQL statement in the application lives here.
 *
 * Services above this file deal in plain objects and never see a query, which is
 * what keeps the storage engine swappable and keeps SQL out of business logic.
 */

// ─── Types ────────────────────────────────────────────────────────────────────

export interface IndexerState {
  chain: ChainKey;
  lastBlock: number;
  lastBlockHash: string | null;
  startBlock: number;
  eventsIndexed: number;
  reorgsHandled: number;
  lastRunAt: number | null;
  lastError: string | null;
}

export interface EventRow {
  id: number;
  chain: ChainKey;
  blockNumber: number;
  blockHash: string;
  txHash: string;
  logIndex: number;
  timestamp: number;
  eventName: string;
  kind: string;
  userAddress: string | null;
  tokenAddress: string | null;
  tokenSymbol: string | null;
  tokenDecimals: number | null;
  amount: string | null;
  args: Record<string, string>;
}

export type NewEvent = Omit<EventRow, "id" | "args"> & { args: Record<string, string> };

export interface ProtocolSnapshot {
  chain: ChainKey;
  blockNumber: number;
  timestamp: number;
  tvlUsd: string;
  borrowedUsd: string;
  collateralUsd: string;
  suppliedUsd: string;
  lpTokenValueUsd: string;
  avgSupplyApr: number;
}

export interface MarketSnapshot {
  chain: ChainKey;
  tokenId: number;
  symbol: string;
  blockNumber: number;
  timestamp: number;
  totalLiquidity: string;
  totalCollateral: string;
  totalBorrowed: string;
  priceUsd: string;
  liquidityUsd: string;
  collateralUsd: string;
  utilization: number;
  borrowApr: number;
  supplyApr: number;
}

export interface CcipMessageRow {
  messageId: string;
  sourceChain: ChainKey;
  destChain: ChainKey | null;
  destSelector: string;
  sender: string;
  receiver: string;
  userAddress: string | null;
  action: string | null;
  feePaid: string | null;
  status: "pending" | "delivered" | "failed";
  sentTx: string;
  sentBlock: number;
  sentAt: number;
  deliveredTx: string | null;
  deliveredBlock: number | null;
  deliveredAt: number | null;
  error: string | null;
}

// ─── Indexer cursor ───────────────────────────────────────────────────────────

export const indexerRepo = {
  get(chain: ChainKey): IndexerState | null {
    const row = getDb()
      .prepare(`SELECT * FROM indexer_state WHERE chain = ?`)
      .get(chain) as Record<string, unknown> | undefined;
    return row ? mapIndexerState(row) : null;
  },

  all(): IndexerState[] {
    const rows = getDb().prepare(`SELECT * FROM indexer_state`).all() as Record<string, unknown>[];
    return rows.map(mapIndexerState);
  },

  init(chain: ChainKey, startBlock: number): void {
    getDb()
      .prepare(
        `INSERT INTO indexer_state (chain, last_block, start_block)
         VALUES (?, ?, ?)
         ON CONFLICT(chain) DO NOTHING`
      )
      .run(chain, startBlock, startBlock);
  },

  advance(chain: ChainKey, block: number, blockHash: string | null, newEvents: number): void {
    getDb()
      .prepare(
        `UPDATE indexer_state
            SET last_block = ?, last_block_hash = ?,
                events_indexed = events_indexed + ?,
                last_run_at = ?, last_error = NULL
          WHERE chain = ?`
      )
      .run(block, blockHash, newEvents, nowSeconds(), chain);
  },

  /** Rolls the cursor back and drops anything indexed above it. */
  rollback(chain: ChainKey, toBlock: number): void {
    transaction(() => {
      getDb().prepare(`DELETE FROM events WHERE chain = ? AND block_number > ?`).run(chain, toBlock);
      getDb()
        .prepare(`DELETE FROM protocol_snapshots WHERE chain = ? AND block_number > ?`)
        .run(chain, toBlock);
      getDb()
        .prepare(`DELETE FROM market_snapshots WHERE chain = ? AND block_number > ?`)
        .run(chain, toBlock);
      getDb()
        .prepare(
          `UPDATE indexer_state
              SET last_block = ?, last_block_hash = NULL,
                  reorgs_handled = reorgs_handled + 1
            WHERE chain = ?`
        )
        .run(toBlock, chain);
    });
  },

  recordError(chain: ChainKey, message: string): void {
    getDb()
      .prepare(`UPDATE indexer_state SET last_error = ?, last_run_at = ? WHERE chain = ?`)
      .run(message, nowSeconds(), chain);
  },
};

// ─── Events ───────────────────────────────────────────────────────────────────

export const eventRepo = {
  /** Inserts a batch idempotently; returns how many rows were actually new. */
  insertMany(events: NewEvent[]): number {
    if (events.length === 0) return 0;

    const insert = getDb().prepare(
      `INSERT OR IGNORE INTO events
         (chain, block_number, block_hash, tx_hash, log_index, timestamp,
          event_name, kind, user_address, token_address, token_symbol,
          token_decimals, amount, args_json)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );
    const touchParticipant = getDb().prepare(
      `INSERT INTO participants (chain, address, first_seen, last_seen, event_count)
       VALUES (?, ?, ?, ?, 1)
       ON CONFLICT(chain, address) DO UPDATE
         SET last_seen = excluded.last_seen, event_count = event_count + 1`
    );

    return transaction(() => {
      let inserted = 0;
      for (const event of events) {
        const result = insert.run(
          event.chain,
          event.blockNumber,
          event.blockHash,
          event.txHash,
          event.logIndex,
          event.timestamp,
          event.eventName,
          event.kind,
          event.userAddress,
          event.tokenAddress,
          event.tokenSymbol,
          event.tokenDecimals,
          event.amount,
          JSON.stringify(event.args)
        );
        if (result.changes > 0) {
          inserted++;
          if (event.userAddress) {
            touchParticipant.run(event.chain, event.userAddress, event.timestamp, event.timestamp);
          }
        }
      }
      return inserted;
    });
  },

  forUser(chain: ChainKey, address: string, limit: number, beforeId?: number): EventRow[] {
    const rows = getDb()
      .prepare(
        `SELECT * FROM events
          WHERE chain = ? AND user_address = ?
            AND (? IS NULL OR id < ?)
          ORDER BY block_number DESC, log_index DESC
          LIMIT ?`
      )
      .all(chain, address.toLowerCase(), beforeId ?? null, beforeId ?? null, limit) as Record<
      string,
      unknown
    >[];
    return rows.map(mapEvent);
  },

  recent(chain: ChainKey, limit: number): EventRow[] {
    const rows = getDb()
      .prepare(
        `SELECT * FROM events WHERE chain = ?
          ORDER BY block_number DESC, log_index DESC LIMIT ?`
      )
      .all(chain, limit) as Record<string, unknown>[];
    return rows.map(mapEvent);
  },

  countForUser(chain: ChainKey, address: string): number {
    const row = getDb()
      .prepare(`SELECT COUNT(*) AS n FROM events WHERE chain = ? AND user_address = ?`)
      .get(chain, address.toLowerCase()) as { n: number };
    return row.n;
  },

  /**
   * Outstanding borrowed principal, summed from the event stream.
   *
   * The protocol's own `getTotalBorroweedForAToken` is permanently zero — the
   * contracts only ever touch that counter inside `liquidate()`, and with a
   * literal 0, so borrowing never increments it. Aggregate debt is therefore not
   * answerable on-chain at all. Summing indexed borrows against repayments is,
   * which is precisely the sort of question an indexer exists to answer.
   *
   * Amounts are stablecoin smallest-units; the caller scales to USD.
   */
  outstandingBorrowed(): { borrowed: string; repaid: string } {
    // Deliberately across every chain, not one. A loan drawn on the hub can be
    // repaid from a satellite, so a per-chain figure would report debt that was
    // already settled elsewhere.
    const row = getDb()
      .prepare(
        `SELECT
           COALESCE(SUM(CASE WHEN kind = 'borrow' THEN CAST(amount AS REAL) END), 0) AS borrowed,
           COALESCE(SUM(CASE WHEN kind = 'repay'  THEN CAST(amount AS REAL) END), 0) AS repaid
         FROM events
         WHERE amount IS NOT NULL`
      )
      .get() as { borrowed: number; repaid: number };

    // CAST(... AS REAL) is lossy past 2^53, but stablecoin totals in a demo stay
    // far below that and SQLite cannot sum decimal strings any other way.
    return {
      borrowed: BigInt(Math.round(row.borrowed)).toString(),
      repaid: BigInt(Math.round(row.repaid)).toString(),
    };
  },

  /** Event totals by kind — powers the protocol activity breakdown. */
  countsByKind(chain: ChainKey): { kind: string; count: number }[] {
    return getDb()
      .prepare(
        `SELECT kind, COUNT(*) AS count FROM events WHERE chain = ?
          GROUP BY kind ORDER BY count DESC`
      )
      .all(chain) as { kind: string; count: number }[];
  },
};

// ─── Snapshots ────────────────────────────────────────────────────────────────

export const snapshotRepo = {
  insertProtocol(snapshot: ProtocolSnapshot): void {
    getDb()
      .prepare(
        `INSERT OR REPLACE INTO protocol_snapshots
           (chain, block_number, timestamp, tvl_usd, borrowed_usd, collateral_usd,
            supplied_usd, lp_token_value_usd, avg_supply_apr)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        snapshot.chain,
        snapshot.blockNumber,
        snapshot.timestamp,
        snapshot.tvlUsd,
        snapshot.borrowedUsd,
        snapshot.collateralUsd,
        snapshot.suppliedUsd,
        snapshot.lpTokenValueUsd,
        snapshot.avgSupplyApr
      );
  },

  insertMarkets(snapshots: MarketSnapshot[]): void {
    if (snapshots.length === 0) return;
    const insert = getDb().prepare(
      `INSERT OR REPLACE INTO market_snapshots
         (chain, token_id, symbol, block_number, timestamp, total_liquidity,
          total_collateral, total_borrowed, price_usd, liquidity_usd,
          collateral_usd, utilization, borrow_apr, supply_apr)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );
    transaction(() => {
      for (const s of snapshots) {
        insert.run(
          s.chain,
          s.tokenId,
          s.symbol,
          s.blockNumber,
          s.timestamp,
          s.totalLiquidity,
          s.totalCollateral,
          s.totalBorrowed,
          s.priceUsd,
          s.liquidityUsd,
          s.collateralUsd,
          s.utilization,
          s.borrowApr,
          s.supplyApr
        );
      }
    });
  },

  protocolHistory(chain: ChainKey, sinceSeconds: number, limit: number): ProtocolSnapshot[] {
    const rows = getDb()
      .prepare(
        `SELECT * FROM protocol_snapshots
          WHERE chain = ? AND timestamp >= ?
          ORDER BY timestamp ASC
          LIMIT ?`
      )
      .all(chain, sinceSeconds, limit) as Record<string, unknown>[];
    return rows.map(mapProtocolSnapshot);
  },

  marketHistory(
    chain: ChainKey,
    tokenId: number,
    sinceSeconds: number,
    limit: number
  ): MarketSnapshot[] {
    const rows = getDb()
      .prepare(
        `SELECT * FROM market_snapshots
          WHERE chain = ? AND token_id = ? AND timestamp >= ?
          ORDER BY timestamp ASC
          LIMIT ?`
      )
      .all(chain, tokenId, sinceSeconds, limit) as Record<string, unknown>[];
    return rows.map(mapMarketSnapshot);
  },

  latestProtocol(chain: ChainKey): ProtocolSnapshot | null {
    const row = getDb()
      .prepare(`SELECT * FROM protocol_snapshots WHERE chain = ? ORDER BY timestamp DESC LIMIT 1`)
      .get(chain) as Record<string, unknown> | undefined;
    return row ? mapProtocolSnapshot(row) : null;
  },
};

// ─── Cross-chain messages ─────────────────────────────────────────────────────

export const ccipRepo = {
  recordSent(message: Omit<CcipMessageRow, "status" | "deliveredTx" | "deliveredBlock" | "deliveredAt" | "error">): void {
    getDb()
      .prepare(
        // The relayer can report a delivery before the indexer has seen the
        // send — it polls every couple of seconds, and delivery is faster than
        // that. So this fills in the send details without touching `status`,
        // which the delivery report owns.
        `INSERT INTO ccip_messages
           (message_id, source_chain, dest_chain, dest_selector, sender, receiver,
            user_address, action, fee_paid, status, sent_tx, sent_block, sent_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)
         ON CONFLICT(message_id) DO UPDATE SET
           source_chain = excluded.source_chain,
           dest_chain   = excluded.dest_chain,
           sender       = excluded.sender,
           receiver     = excluded.receiver,
           user_address = COALESCE(excluded.user_address, user_address),
           action       = COALESCE(excluded.action, action),
           fee_paid     = excluded.fee_paid,
           sent_tx      = excluded.sent_tx,
           sent_block   = excluded.sent_block,
           sent_at      = excluded.sent_at`
      )
      .run(
        message.messageId,
        message.sourceChain,
        message.destChain,
        message.destSelector,
        message.sender,
        message.receiver,
        message.userAddress,
        message.action,
        message.feePaid,
        message.sentTx,
        message.sentBlock,
        message.sentAt
      );
  },

  /**
   * Records a delivery outcome, whether or not the send has been indexed yet.
   *
   * Delivery routinely beats indexing, so a plain UPDATE would silently drop the
   * result and leave the message pending forever. Inserting a stub instead lets
   * the indexer fill in the send details later without overwriting the status.
   */
  markDelivered(messageId: string, tx: string, block: number): void {
    getDb()
      .prepare(
        `INSERT INTO ccip_messages
           (message_id, source_chain, dest_selector, sender, receiver,
            status, sent_tx, sent_block, sent_at,
            delivered_tx, delivered_block, delivered_at)
         VALUES (?, '', '', '', '', 'delivered', '', 0, ?, ?, ?, ?)
         ON CONFLICT(message_id) DO UPDATE SET
           status = 'delivered', delivered_tx = excluded.delivered_tx,
           delivered_block = excluded.delivered_block,
           delivered_at = excluded.delivered_at`
      )
      .run(messageId, nowSeconds(), tx, block, nowSeconds());
  },

  markFailed(messageId: string, error: string): void {
    getDb()
      .prepare(
        `INSERT INTO ccip_messages
           (message_id, source_chain, dest_selector, sender, receiver,
            status, sent_tx, sent_block, sent_at, error)
         VALUES (?, '', '', '', '', 'failed', '', 0, ?, ?)
         ON CONFLICT(message_id) DO UPDATE SET status = 'failed', error = excluded.error`
      )
      .run(messageId, nowSeconds(), error);
  },

  recent(limit: number): CcipMessageRow[] {
    const rows = getDb()
      .prepare(`SELECT * FROM ccip_messages ORDER BY sent_at DESC LIMIT ?`)
      .all(limit) as Record<string, unknown>[];
    return rows.map(mapCcipMessage);
  },

  pending(): CcipMessageRow[] {
    const rows = getDb()
      .prepare(`SELECT * FROM ccip_messages WHERE status = 'pending' ORDER BY sent_at ASC`)
      .all() as Record<string, unknown>[];
    return rows.map(mapCcipMessage);
  },

  forUser(address: string, limit: number): CcipMessageRow[] {
    const rows = getDb()
      .prepare(`SELECT * FROM ccip_messages WHERE user_address = ? ORDER BY sent_at DESC LIMIT ?`)
      .all(address.toLowerCase(), limit) as Record<string, unknown>[];
    return rows.map(mapCcipMessage);
  },

  stats(): { total: number; delivered: number; pending: number; failed: number; avgLatencyMs: number } {
    const row = getDb()
      .prepare(
        `SELECT
           COUNT(*) AS total,
           SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) AS delivered,
           SUM(CASE WHEN status = 'pending'   THEN 1 ELSE 0 END) AS pending,
           SUM(CASE WHEN status = 'failed'    THEN 1 ELSE 0 END) AS failed,
           -- sent_at is a block timestamp and delivered_at is wall clock.
           -- A demo that fast-forwards chain time makes that difference
           -- negative and meaningless, so those rows are excluded rather than
           -- dragging the average below zero.
           AVG(CASE WHEN delivered_at IS NOT NULL AND delivered_at >= sent_at
                    THEN (delivered_at - sent_at) END) AS avg_latency
         FROM ccip_messages`
      )
      .get() as Record<string, number | null>;

    return {
      total: row.total ?? 0,
      delivered: row.delivered ?? 0,
      pending: row.pending ?? 0,
      failed: row.failed ?? 0,
      avgLatencyMs: Math.round((row.avg_latency ?? 0) * 1000),
    };
  },
};

// ─── Participants ─────────────────────────────────────────────────────────────

export const participantRepo = {
  count(chain: ChainKey): number {
    const row = getDb()
      .prepare(`SELECT COUNT(*) AS n FROM participants WHERE chain = ?`)
      .get(chain) as { n: number };
    return row.n;
  },

  top(chain: ChainKey, limit: number): { address: string; eventCount: number; lastSeen: number }[] {
    return getDb()
      .prepare(
        `SELECT address, event_count AS eventCount, last_seen AS lastSeen
           FROM participants WHERE chain = ?
          ORDER BY event_count DESC LIMIT ?`
      )
      .all(chain, limit) as { address: string; eventCount: number; lastSeen: number }[];
  },
};

// ─── Row mappers ──────────────────────────────────────────────────────────────

function mapIndexerState(row: Record<string, unknown>): IndexerState {
  return {
    chain: row.chain as ChainKey,
    lastBlock: row.last_block as number,
    lastBlockHash: (row.last_block_hash as string) ?? null,
    startBlock: row.start_block as number,
    eventsIndexed: row.events_indexed as number,
    reorgsHandled: row.reorgs_handled as number,
    lastRunAt: (row.last_run_at as number) ?? null,
    lastError: (row.last_error as string) ?? null,
  };
}

function mapEvent(row: Record<string, unknown>): EventRow {
  return {
    id: row.id as number,
    chain: row.chain as ChainKey,
    blockNumber: row.block_number as number,
    blockHash: row.block_hash as string,
    txHash: row.tx_hash as string,
    logIndex: row.log_index as number,
    timestamp: row.timestamp as number,
    eventName: row.event_name as string,
    kind: row.kind as string,
    userAddress: (row.user_address as string) ?? null,
    tokenAddress: (row.token_address as string) ?? null,
    tokenSymbol: (row.token_symbol as string) ?? null,
    tokenDecimals: (row.token_decimals as number) ?? null,
    amount: (row.amount as string) ?? null,
    args: JSON.parse(row.args_json as string) as Record<string, string>,
  };
}

function mapProtocolSnapshot(row: Record<string, unknown>): ProtocolSnapshot {
  return {
    chain: row.chain as ChainKey,
    blockNumber: row.block_number as number,
    timestamp: row.timestamp as number,
    tvlUsd: row.tvl_usd as string,
    borrowedUsd: row.borrowed_usd as string,
    collateralUsd: row.collateral_usd as string,
    suppliedUsd: row.supplied_usd as string,
    lpTokenValueUsd: row.lp_token_value_usd as string,
    avgSupplyApr: row.avg_supply_apr as number,
  };
}

function mapMarketSnapshot(row: Record<string, unknown>): MarketSnapshot {
  return {
    chain: row.chain as ChainKey,
    tokenId: row.token_id as number,
    symbol: row.symbol as string,
    blockNumber: row.block_number as number,
    timestamp: row.timestamp as number,
    totalLiquidity: row.total_liquidity as string,
    totalCollateral: row.total_collateral as string,
    totalBorrowed: row.total_borrowed as string,
    priceUsd: row.price_usd as string,
    liquidityUsd: row.liquidity_usd as string,
    collateralUsd: row.collateral_usd as string,
    utilization: row.utilization as number,
    borrowApr: row.borrow_apr as number,
    supplyApr: row.supply_apr as number,
  };
}

function mapCcipMessage(row: Record<string, unknown>): CcipMessageRow {
  return {
    messageId: row.message_id as string,
    sourceChain: row.source_chain as ChainKey,
    destChain: (row.dest_chain as ChainKey) ?? null,
    destSelector: row.dest_selector as string,
    sender: row.sender as string,
    receiver: row.receiver as string,
    userAddress: (row.user_address as string) ?? null,
    action: (row.action as string) ?? null,
    feePaid: (row.fee_paid as string) ?? null,
    status: row.status as CcipMessageRow["status"],
    sentTx: row.sent_tx as string,
    sentBlock: row.sent_block as number,
    sentAt: row.sent_at as number,
    deliveredTx: (row.delivered_tx as string) ?? null,
    deliveredBlock: (row.delivered_block as number) ?? null,
    deliveredAt: (row.delivered_at as number) ?? null,
    error: (row.error as string) ?? null,
  };
}

function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}
