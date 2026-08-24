/**
 * Minimal in-process TTL cache.
 *
 * Read endpoints (markets, token metadata, prices) fan out to a dozen RPC calls
 * each. Without caching, a dashboard polling every few seconds burns through
 * provider rate limits. Values are small and the process is single-node, so a
 * Map with expiry timestamps is sufficient — no Redis dependency.
 */

interface Entry<T> {
  value: T;
  expiresAt: number;
}

const store = new Map<string, Entry<unknown>>();

/** In-flight promises, keyed identically — collapses concurrent misses into one call. */
const inflight = new Map<string, Promise<unknown>>();

/**
 * Returns the cached value for `key`, or computes it with `producer` and caches
 * the result for `ttlMs`. Concurrent callers with the same key share one call.
 */
export async function cached<T>(key: string, ttlMs: number, producer: () => Promise<T>): Promise<T> {
  const now = Date.now();
  const hit = store.get(key);
  if (hit && hit.expiresAt > now) return hit.value as T;

  const pending = inflight.get(key);
  if (pending) return pending as Promise<T>;

  const promise = producer()
    .then((value) => {
      store.set(key, { value, expiresAt: Date.now() + ttlMs });
      return value;
    })
    .finally(() => {
      inflight.delete(key);
    });

  inflight.set(key, promise);
  return promise;
}

/** Drops every entry whose key starts with `prefix`. Call after a write lands. */
export function invalidatePrefix(prefix: string): void {
  for (const key of store.keys()) {
    if (key.startsWith(prefix)) store.delete(key);
  }
}

/** Clears the entire cache. Used by tests and the admin reset endpoint. */
export function clearCache(): void {
  store.clear();
}
