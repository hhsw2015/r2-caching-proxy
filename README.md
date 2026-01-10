# r2-caching-proxy
Cloudflare pages site that simply proxies to an R2 bucket and caches responses


### 部署与调试


#### 1. 切换 Node.js 版本
```bash
nvm use 20.19.5
```

#### 2. 登录 Cloudflare
授权 Wrangler 访问您的 Cloudflare 账户。这是一个一次性操作。
```bash
npx wrangler login
```

#### 3. 配置项目
**在部署前，您必须修改 `wrangler.toml` 文件。**
打开 `wrangler.toml` 并更新以下字段：
- `name`: 您在 Cloudflare Pages 上的项目名称。
- `r2_buckets`:
  - `bucket_name`: 您要代理的 R2 存储桶的**真实名称**。
- `vars`: (可选)
  - `MAX_AGE`: CDN 缓存的秒数 (例如 `31536000` 代表一年)。

```toml
# 示例 wrangler.toml
name = "my-r2-proxy" # <-- 修改这里

[[r2_buckets]]
binding = "PROXY_BUCKET"
bucket_name = "your-actual-bucket-name" # <-- 修改这里

[vars]
MAX_AGE = "31536000"
```

#### 4. 部署到 Cloudflare Pages
此命令会读取您修改后的 `wrangler.toml` 并将项目部署到 Cloudflare。
```bash
npx wrangler pages deploy .
```

#### 5. 查找生产域名
部署成功后，运行此命令列出您所有的 Pages 项目，从中找到您项目的“Production URL”。
```bash
npx wrangler pages project list
```

#### 6. 查看实时日志
连接到已部署的应用，实时监控函数日志，用于调试。
```bash

npx wrangler pages deployment tail
```
