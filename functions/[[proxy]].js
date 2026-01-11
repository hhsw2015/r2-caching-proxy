// Adapted from R2 example code at https://developers.cloudflare.com/r2/examples/cache-api/

export async function onRequest(context) {
  try {
    const maxage = context.env.MAX_AGE || 3600;
    const { request } = context;
    const url = new URL(request.url);

    // === THE ULTIMATE, SIMPLIFIED CACHE KEY NORMALIZATION ===
    // 1. Double-decode the pathname to get the absolute, "clean" path string with real spaces.
    const fullyDecodedPathname = decodeURIComponent(decodeURIComponent(url.pathname));

    // 2. Directly construct the canonical URL string. This is cleaner and more direct.
    //    The browser will automatically re-encode the spaces to %20 when creating the Request object.
    const canonicalUrlString = `${url.protocol}//${url.hostname}${fullyDecodedPathname}`;
    
    // 3. The one and only cache key.
    const cacheKey = new Request(canonicalUrlString, request);
    // =========================================================

    const cache = caches.default;
    const cacheResponse = await cache.match(cacheKey);

    if (cacheResponse) {
      console.log(`✅ Cache hit for canonical key constructed from: "${canonicalUrlString}"`);
      return cacheResponse;
    }
    console.log(`Cache miss for canonical key. Fetching from R2...`);

    // --- R2 Fetching Logic (now simplified) ---
    // We already have the perfectly decoded key for R2.
    const objectKey = fullyDecodedPathname.slice(1);
    
    console.log(`Attempting to get object from R2 with key: "${objectKey}"`);
    const object = await context.env.PROXY_BUCKET.get(objectKey);

    if (object === null) {
      return new Response('Object Not Found', { status: 404 });
    }

    // Set the appropriate object headers
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('etag', object.httpEtag);

    // Cache API respects Cache-Control headers. Setting s-max-age to 10
    // will limit the response to be in cache for 10 seconds max
    // Any changes made to the response here will be reflected in the cached value
    headers.append('Cache-Control', `s-maxage=${maxage}`);

    const response = new Response(object.body, {
      headers,
    });

    // Unconditionally attempt to cache the response.
    context.waitUntil(cache.put(cacheKey, response.clone()));
    console.log(`Attempting to store response in cache for key constructed from: "${canonicalUrlString}"`);


    return response;
  } catch (e) {
    return new Response('Error thrown ' + e.message, { status: 500 });
  }
}
