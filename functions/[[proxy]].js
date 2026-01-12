// The definitive onRequest function (v5.4 - Dual Mode).
// It intelligently switches between a high-performance 302 redirect mode (for large files via CDN)
// and a fallback Cache API mode, based on an environment variable.

function decodeSegment(segment, passes) {
  let decoded = segment;
  for (let i = 0; i < passes; i += 1) {
    try {
      decoded = decodeURIComponent(decoded);
    } catch {
      break;
    }
  }
  return decoded;
}

function shouldTryDoubleDecode(pathname) {
  return /%25[0-9A-Fa-f]{2}/.test(pathname);
}

function normalizePathname(pathname, passes) {
  const segments = pathname.split('/');
  const normalizedSegments = segments.map((segment) => {
    if (segment === '') {
      return '';
    }

    const decoded = decodeSegment(segment, passes);
    return encodeURIComponent(decoded);
  });

  return normalizedSegments.join('/');
}

async function resolveObjectKey(env, pathname) {
  const normalizedOnce = normalizePathname(pathname, 1);
  const keyOnce = normalizedOnce.startsWith('/') ? normalizedOnce.slice(1) : normalizedOnce;

  if (!shouldTryDoubleDecode(pathname)) {
    return { key: keyOnce, pathname: normalizedOnce };
  }

  const normalizedTwice = normalizePathname(pathname, 2);
  const keyTwice = normalizedTwice.startsWith('/') ? normalizedTwice.slice(1) : normalizedTwice;

  if (keyOnce === keyTwice) {
    const head = await env.PROXY_BUCKET.head(keyOnce);
    return head ? { key: keyOnce, pathname: normalizedOnce } : null;
  }

  const headOnce = await env.PROXY_BUCKET.head(keyOnce);
  if (headOnce) {
    return { key: keyOnce, pathname: normalizedOnce };
  }

  const headTwice = await env.PROXY_BUCKET.head(keyTwice);
  if (headTwice) {
    return { key: keyTwice, pathname: normalizedTwice };
  }

  return null;
}

function buildCacheKey(canonicalUrl) {
  return new Request(canonicalUrl, { method: 'GET' });
}

export async function onRequest(context) {
  try {
    const { request, env } = context;
    const url = new URL(request.url);

    // --- ⭐ 核心切换逻辑: 检查是否存在 R2 自定义域名配置 ⭐ ---
    const R2_CUSTOM_DOMAIN = env.R2_CUSTOM_DOMAIN;

    if (R2_CUSTOM_DOMAIN) {
      // --- 🚀 模式一: 高性能重定向模式 (用于大文件和 CDN 缓存) ---
      console.log(`[Redirect] Detected R2_CUSTOM_DOMAIN: "${R2_CUSTOM_DOMAIN}". Engaging redirect mode.`);

      // 1. 规范化路径并探测对象，兼容一次/二次编码
      const resolved = await resolveObjectKey(env, url.pathname);
      const normalizedPathname = resolved ? resolved.pathname : normalizePathname(url.pathname, 1);

      // 2. 构造指向 R2 自定义域名的规范化 URL
      const r2Url = `https://${R2_CUSTOM_DOMAIN}${normalizedPathname}`;

      console.log(`[Redirect] Redirecting to clean R2 URL: "${r2Url}"`);

      // 3. 返回 302 临时重定向。浏览器将向这个新 URL 发出请求，
      //    该请求会被 Cloudflare 的标准 CDN 缓存高效处理。
      return new Response(null, {
        status: 302,
        headers: {
          Location: r2Url,
        },
      });
    }

    // --- 🎒 模式二: Cache API 备用模式 (用于无自定义域名或小文件) ---
    console.log('[CacheAPI] R2_CUSTOM_DOMAIN not set. Engaging Cache API mode.');

    const maxage = env.MAX_AGE || 3600;

    const normalizedOnce = normalizePathname(url.pathname, 1);
    const canonicalUrlOnce = `${url.protocol}//${url.hostname}${normalizedOnce}`;
    const cacheKeyOnce = buildCacheKey(canonicalUrlOnce);

    const cache = caches.default;
    const cacheResponseOnce = await cache.match(cacheKeyOnce);

    if (cacheResponseOnce) {
      console.log(`[CacheAPI] ✅ Cache hit for canonical key: "${canonicalUrlOnce}"`);
      return cacheResponseOnce;
    }

    const tryDoubleDecode = shouldTryDoubleDecode(url.pathname);
    const normalizedTwice = tryDoubleDecode ? normalizePathname(url.pathname, 2) : normalizedOnce;
    const canonicalUrlTwice = `${url.protocol}//${url.hostname}${normalizedTwice}`;
    const cacheKeyTwice = buildCacheKey(canonicalUrlTwice);

    if (tryDoubleDecode && canonicalUrlTwice !== canonicalUrlOnce) {
      const cacheResponseTwice = await cache.match(cacheKeyTwice);
      if (cacheResponseTwice) {
        console.log(`[CacheAPI] ✅ Cache hit for canonical key: "${canonicalUrlTwice}"`);
        return cacheResponseTwice;
      }
    }

    console.log('[CacheAPI] Cache miss. Fetching from R2...');

    // 2. R2 查找逻辑 (先一次编码再二次编码)
    const objectKeyOnce = normalizedOnce.startsWith('/') ? normalizedOnce.slice(1) : normalizedOnce;
    let object = await env.PROXY_BUCKET.get(objectKeyOnce);
    let normalizedPathname = normalizedOnce;
    let cacheKey = cacheKeyOnce;
    let canonicalUrlString = canonicalUrlOnce;

    if (tryDoubleDecode && object === null && canonicalUrlTwice !== canonicalUrlOnce) {
      const objectKeyTwice = normalizedTwice.startsWith('/') ? normalizedTwice.slice(1) : normalizedTwice;
      const objectTwice = await env.PROXY_BUCKET.get(objectKeyTwice);
      if (objectTwice) {
        object = objectTwice;
        normalizedPathname = normalizedTwice;
        cacheKey = cacheKeyTwice;
        canonicalUrlString = canonicalUrlTwice;
      }
    }

    if (object === null) {
      const notFoundHeaders = new Headers({
        'Cache-Control': 's-maxage=60',
      });
      const notFoundResponse = new Response('Object Not Found', {
        status: 404,
        headers: notFoundHeaders,
      });

      context.waitUntil(cache.put(cacheKeyOnce, notFoundResponse.clone()));
      if (tryDoubleDecode && canonicalUrlTwice !== canonicalUrlOnce) {
        context.waitUntil(cache.put(cacheKeyTwice, notFoundResponse.clone()));
      }

      return notFoundResponse;
    }

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('etag', object.httpEtag);
    if (!headers.has('Cache-Control')) {
      headers.set('Cache-Control', `s-maxage=${maxage}`);
    }

    const response = new Response(object.body, { headers });

    // 3. 无条件尝试缓存
    context.waitUntil(cache.put(cacheKey, response.clone()));
    console.log(`[CacheAPI] Attempting to store response in cache for key: "${canonicalUrlString}"`);

    return response;
  } catch (e) {
    console.error('A critical error was thrown:', e);
    return new Response('Error thrown: ' + e.message, { status: 500 });
  }
}
