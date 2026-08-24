-- AstraLend indexer schema.
--
-- Design notes that apply throughout:
--
-- * Every uint256 is stored as TEXT. SQLite's INTEGER tops out at 2^63 and
--   silently loses precision above it; wei values routinely exceed that. Ordering
--   is never done on these columns, only on block numbers and timestamps.
-- * `chain` is the ChainKey ("eth" | "arb"), not the numeric id, so it matches
--   the API surface and the config keys directly.
-- * Timestamps are unix seconds (INTEGER), taken from the block header rather
--   than wall-clock, so a time-travelled local chain stays internally consistent.

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- ─── Indexer cursor ──────────────────────────────────────────────────────────
-- One row per chain. `last_block_hash` is what makes reorg detection possible:
-- on each pass the indexer re-reads that block and compares hashes.

CREATE TABLE IF NOT EXISTS indexer_state (
  chain            TEXT PRIMARY KEY,
  last_block       INTEGER NOT NULL DEFAULT 0,
  last_block_hash  TEXT,
  start_block      INTEGER NOT NULL DEFAULT 0,
  events_indexed   INTEGER NOT NULL DEFAULT 0,
  reorgs_handled   INTEGER NOT NULL DEFAULT 0,
  last_run_at      INTEGER,
  last_error       TEXT
);

-- ─── Protocol events ─────────────────────────────────────────────────────────
-- The decoded log stream. This is what the activity feed reads instead of
-- re-scanning the chain on every request.

CREATE TABLE IF NOT EXISTS events (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  chain          TEXT    NOT NULL,
  block_number   INTEGER NOT NULL,
  block_hash     TEXT    NOT NULL,
  tx_hash        TEXT    NOT NULL,
  log_index      INTEGER NOT NULL,
  timestamp      INTEGER NOT NULL,
  event_name     TEXT    NOT NULL,
  kind           TEXT    NOT NULL,
  user_address   TEXT,
  token_address  TEXT,
  token_symbol   TEXT,
  token_decimals INTEGER,
  amount         TEXT,
  args_json      TEXT    NOT NULL,
  -- A log is uniquely identified by its transaction and position within it.
  -- Re-indexing the same block is therefore a no-op rather than a duplicate.
  UNIQUE (chain, tx_hash, log_index)
);

CREATE INDEX IF NOT EXISTS idx_events_user
  ON events (chain, user_address, block_number DESC, log_index DESC);
CREATE INDEX IF NOT EXISTS idx_events_block
  ON events (chain, block_number DESC);
CREATE INDEX IF NOT EXISTS idx_events_kind
  ON events (chain, kind, block_number DESC);

-- ─── Protocol-wide time series ───────────────────────────────────────────────
-- Chain state only ever exposes "now". These rows are the only way to answer
-- "what was TVL an hour ago", which is what the dashboard charts plot.

CREATE TABLE IF NOT EXISTS protocol_snapshots (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  chain               TEXT    NOT NULL,
  block_number        INTEGER NOT NULL,
  timestamp           INTEGER NOT NULL,
  tvl_usd             TEXT    NOT NULL,
  borrowed_usd        TEXT    NOT NULL,
  collateral_usd      TEXT    NOT NULL,
  supplied_usd        TEXT    NOT NULL,
  lp_token_value_usd  TEXT    NOT NULL,
  avg_supply_apr      REAL    NOT NULL,
  UNIQUE (chain, block_number)
);

CREATE INDEX IF NOT EXISTS idx_protocol_snapshots_time
  ON protocol_snapshots (chain, timestamp DESC);

-- ─── Per-market time series ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS market_snapshots (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  chain            TEXT    NOT NULL,
  token_id         INTEGER NOT NULL,
  symbol           TEXT    NOT NULL,
  block_number     INTEGER NOT NULL,
  timestamp        INTEGER NOT NULL,
  total_liquidity  TEXT    NOT NULL,
  total_collateral TEXT    NOT NULL,
  total_borrowed   TEXT    NOT NULL,
  price_usd        TEXT    NOT NULL,
  liquidity_usd    TEXT    NOT NULL,
  collateral_usd   TEXT    NOT NULL,
  utilization      REAL    NOT NULL,
  borrow_apr       REAL    NOT NULL,
  supply_apr       REAL    NOT NULL,
  UNIQUE (chain, token_id, block_number)
);

CREATE INDEX IF NOT EXISTS idx_market_snapshots_time
  ON market_snapshots (chain, token_id, timestamp DESC);

-- ─── Cross-chain messages ────────────────────────────────────────────────────
-- Survives a relayer restart, which the relayer's own in-memory list does not.
-- `status` moves pending → delivered, or pending → failed if delivery reverts.

CREATE TABLE IF NOT EXISTS ccip_messages (
  message_id       TEXT PRIMARY KEY,
  source_chain     TEXT    NOT NULL,
  dest_chain       TEXT,
  dest_selector    TEXT    NOT NULL,
  sender           TEXT    NOT NULL,
  receiver         TEXT    NOT NULL,
  user_address     TEXT,
  action           TEXT,
  fee_paid         TEXT,
  status           TEXT    NOT NULL DEFAULT 'pending',
  sent_tx          TEXT    NOT NULL,
  sent_block       INTEGER NOT NULL,
  sent_at          INTEGER NOT NULL,
  delivered_tx     TEXT,
  delivered_block  INTEGER,
  delivered_at     INTEGER,
  error            TEXT
);

CREATE INDEX IF NOT EXISTS idx_ccip_status
  ON ccip_messages (status, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_ccip_user
  ON ccip_messages (user_address, sent_at DESC);

-- ─── Known participants ──────────────────────────────────────────────────────
-- Derived from the event stream; powers "unique users" and the activity filter.

CREATE TABLE IF NOT EXISTS participants (
  chain        TEXT    NOT NULL,
  address      TEXT    NOT NULL,
  first_seen   INTEGER NOT NULL,
  last_seen    INTEGER NOT NULL,
  event_count  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (chain, address)
);

-- ─── Real-world asset collateral ─────────────────────────────────────────────
-- A lien is the on-chain half of a recorded pledge. Unlike crypto collateral,
-- which is evidenced by a vault balance, an encumbrance leaves no balance to
-- read — the borrower still holds the tokens. The register is the only record,
-- so it has to be indexed to be queryable.

CREATE TABLE IF NOT EXISTS liens (
  lien_id       TEXT    NOT NULL,
  chain         TEXT    NOT NULL,
  borrower      TEXT    NOT NULL,
  token_address TEXT    NOT NULL,
  amount        TEXT    NOT NULL,
  loan_ref      TEXT,
  perfected_at  INTEGER NOT NULL,
  released_at   INTEGER,
  foreclosed    INTEGER NOT NULL DEFAULT 0,
  tx_hash       TEXT    NOT NULL,
  block_number  INTEGER NOT NULL,
  PRIMARY KEY (chain, lien_id)
);

CREATE INDEX IF NOT EXISTS idx_liens_borrower
  ON liens (chain, borrower, perfected_at DESC);
CREATE INDEX IF NOT EXISTS idx_liens_active
  ON liens (chain, released_at, foreclosed);

-- Eligibility decays: an attestation carries an expiry, and a row that has not
-- been revoked can still be stale. Queries must compare against expiry rather
-- than trusting the flag.
CREATE TABLE IF NOT EXISTS eligibility (
  subject       TEXT    NOT NULL,
  chain         TEXT    NOT NULL,
  jurisdiction  TEXT,
  expiry        INTEGER NOT NULL,
  registered_at INTEGER NOT NULL,
  revoked_at    INTEGER,
  tx_hash       TEXT    NOT NULL,
  PRIMARY KEY (chain, subject)
);

-- A bill's NAV is computed rather than reported, so this is not a feed archive.
-- It exists so the UI can plot accretion toward par without recomputing the
-- curve client-side.
CREATE TABLE IF NOT EXISTS nav_history (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  chain         TEXT    NOT NULL,
  token_address TEXT    NOT NULL,
  nav           TEXT    NOT NULL,
  timestamp     INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_nav_token
  ON nav_history (chain, token_address, timestamp DESC);
