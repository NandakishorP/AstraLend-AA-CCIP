import Database from "better-sqlite3";
import { readFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { env } from "../config/env.js";

const here = dirname(fileURLToPath(import.meta.url));

/**
 * The single process-wide database handle.
 *
 * SQLite is deliberate rather than a placeholder for "real" Postgres. The
 * workload is one writer (the indexer) and a handful of readers in the same
 * process, the dataset is bounded by the chain's own history, and every query
 * here is a keyed lookup or a range scan over an index. Postgres would add an
 * operational dependency — a server to install, start and connect to before the
 * app works — and buy nothing this workload can use.
 *
 * The swap, if it is ever wanted, is contained: every statement lives in
 * `repositories.ts`, and nothing above that layer knows which engine answers.
 */
let db: Database.Database | null = null;

export function getDb(): Database.Database {
  if (db) return db;

  if (env.DATABASE_PATH !== ":memory:") {
    mkdirSync(dirname(env.DATABASE_PATH), { recursive: true });
  }

  db = new Database(env.DATABASE_PATH);

  // WAL lets the API keep reading while the indexer writes. NORMAL synchronous
  // trades a tiny durability window for a large write-throughput win, which is
  // the right trade for data that can always be re-derived from the chain.
  db.pragma("journal_mode = WAL");
  db.pragma("synchronous = NORMAL");
  db.pragma("busy_timeout = 5000");

  const schema = readFileSync(join(here, "schema.sql"), "utf8");
  db.exec(schema);

  return db;
}

/** Closes the handle. Used on shutdown and between tests. */
export function closeDb(): void {
  db?.close();
  db = null;
}

/**
 * Runs `fn` inside a transaction.
 *
 * The indexer writes a block's events, its participants and its cursor update
 * together — a crash between those would leave the cursor claiming work that was
 * never persisted, and the events would be skipped forever.
 */
export function transaction<T>(fn: () => T): T {
  return getDb().transaction(fn)();
}

/** Wipes indexed data without touching the schema. Used by the demo reset. */
export function resetIndexedData(): void {
  transaction(() => {
    const handle = getDb();
    handle.exec("DELETE FROM events");
    handle.exec("DELETE FROM protocol_snapshots");
    handle.exec("DELETE FROM market_snapshots");
    handle.exec("DELETE FROM ccip_messages");
    handle.exec("DELETE FROM participants");
    handle.exec("DELETE FROM indexer_state");
  });
}
