import pkg from 'lru-cache';
const LRUCache = typeof pkg === 'function' ? pkg : pkg.LRUCache;

const rateLimit = (options) => {
  const tokenCache = new LRUCache({
    max: options.uniqueTokenPerInterval || 500,
    ttl: options.interval || 60_000,
  });

  return {
    check: (res, limit, token) =>
      new Promise((resolve, reject) => {
        const tokenCount = tokenCache.get(token) || [0];
        if (tokenCount[0] === 0) tokenCache.set(token, tokenCount);
        tokenCount[0]++;
        const currentUsage = tokenCount[0];
        const isRateLimited = currentUsage > limit;
        res.setHeader('X-RateLimit-Limit', limit);
        res.setHeader('X-RateLimit-Remaining', isRateLimited ? 0 : limit - currentUsage);
        return isRateLimited ? reject() : resolve();
      }),
  };
};

export default rateLimit;