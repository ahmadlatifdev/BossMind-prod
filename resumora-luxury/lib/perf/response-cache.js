/**
 * In-memory TTL cache for hot read-only API responses (per serverless instance).
 */
const store = new Map();

function getCached(key) {
  const row = store.get(key);
  if (!row) return null;
  if (Date.now() > row.expiresAt) {
    store.delete(key);
    return null;
  }
  return row.value;
}

function setCached(key, value, ttlMs) {
  store.set(key, { value, expiresAt: Date.now() + ttlMs });
  if (store.size > 200) {
    const oldest = store.keys().next().value;
    if (oldest) store.delete(oldest);
  }
}

module.exports = { getCached, setCached };
