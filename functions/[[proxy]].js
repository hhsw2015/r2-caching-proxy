// The definitive onRequest function (v5.4 - Dual Mode).
// It intelligently switches between a high-performance 302 redirect mode (for large files via CDN)
// and a fallback Cache API mode, based on an environment variable.

export async function onRequest(context) {
  try {
    const { request, env } = context;
    const url = new URL(request.url);

    // --- ⭐ 核心切换逻辑: 检查是否存在 R2 自定义域名配置 ⭐ ---
    const R2_CUSTOM_DOMAIN = env.R2_CUSTOM_DOMAIN;

    if (R2_CUSTOM_DOMAIN) {
      // --- 🚀 模式一: 高性能重定向模式 (用于大文件和 CDN 缓存) ---
      console.log(`[Redirect] Detected R2_CUSTOM_DOMAIN: "${R2_CUSTOM_DOMAIN}". Engaging redirect mode.`);

      // 1. 净化 URL 路径，进行双重解码得到干净路径
      const fullyDecodedPathname = decodeURIComponent(decodeURIComponent(url.pathname));

      // 2. 构造指向 R2 自定义域名的干净、标准的 URL
      //    我们必须手动将干净路径中的空格等字符重新编码，以生成一个有效的 URL。
      const r2Url = `https://${R2_CUSTOM_DOMAIN}${encodeURIComponent(fullyDecodedPathname.slice(1))}`;
      
      console.log(`[Redirect] Redirecting to clean R2 URL: "${r2Url}"`);

      // 3. 返回 302 临时重定向。浏览器将向这个新 URL 发出请求，
      //    该请求会被 Cloudflare 的标准 CDN 缓存高效处理。
      return new Response(null, {
        status: 302,
        headers: {
          'Location': r2Url,
        },
      });
    } else {
      // --- 🎒 模式二: Cache API 备用模式 (用于无自定义域名或小文件) ---
      console.log(`[CacheAPI] R2_CUSTOM_DOMAIN not set. Engaging Cache API mode.`);
      
      const maxage = env.MAX_AGE || 3600;

      // 1. 终极缓存键规范化
      const fullyDecodedPathname = decodeURIComponent(decodeURIComponent(url.pathname));
      const canonicalUrlString = `${url.protocol}//${url.hostname}${fullyDecodedPathname}`;
      const cacheKey = new Request(canonicalUrlString, request);
      
      const cache = caches.default;
      const cacheResponse = await cache.match(cacheKey);

      if (cacheResponse) {
        console.log(`[CacheAPI] ✅ Cache hit for canonical key: "${canonicalUrlString}"`);
        return cacheResponse;
      }
      console.log(`[CacheAPI] Cache miss. Fetching from R2...`);

      // 2. R2 查找逻辑
      const objectKey = fullyDecodedPathname.slice(1);
      const object = await env.PROXY_BUCKET.get(objectKey);

      if (object === null) {
        return new Response('Object Not Found', { status: 404 });
      }

      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set('etag', object.httpEtag);
      headers.append('Cache-Control', `s-maxage=${maxage}`);

      const response = new Response(object.body, { headers });

      // 3. 无条件尝试缓存
      context.waitUntil(cache.put(cacheKey, response.clone()));
      console.log(`[CacheAPI] Attempting to store response in cache for key: "${canonicalUrlString}"`);

      return response;
    }

  } catch (e) {
    console.error('A critical error was thrown:', e);
    return new Response('Error thrown: ' + e.message, { status: 500 });
  }
}

