#!/bin/bash

# 确保脚本在任何命令失败时立即退出
set -e

# --- 步骤 1: 验证和解析输入 ---
# 检查第一个命令行参数 ($1) 是否为空。
if [ -z "$1" ]; then
  echo "❌ 错误：未提供存储桶名称。"
  echo "   用法: ./deploy.sh <your-bucket-name> [cache-max-age-seconds]"
  echo "   示例: ./deploy.sh my-bucket"
  echo "   示例: ./deploy.sh my-bucket 86400"
  exit 1
fi

# --- 配置 ---
# 从第一个命令行参数获取存储桶名称
BUCKET_NAME="$1"
MAX_AGE=${2:-31536000}
# 项目名称可以保持硬编码，或者也作为第二个参数 ($2) 传入
#PROJECT_NAME="r2-proxy"
PROJECT_NAME="r2-proxy-$BUCKET_NAME"

echo "--- 准备部署项目: $PROJECT_NAME ---"
echo "--- 目标 R2 存储桶: $BUCKET_NAME ---"
echo ""

echo "--- 步骤 2: 登录 Cloudflare (如果需要) ---"
npx wrangler login

echo "--- 步骤 3: 确保 Pages 项目存在 ---"
# 显式创建 Pages 项目。`--production-branch main` 会自动设置生产分支。
# `|| true` 确保如果项目已存在，脚本不会因“项目已存在”的错误而停止。
npx wrangler pages project create $PROJECT_NAME --production-branch main || true

echo "--- 步骤 4: 创建 R2 存储桶 ---"
# npx wrangler r2 bucket delete $BUCKET_NAME
# 尝试创建存储桶。|| true 确保如果桶已存在，脚本不会因错误而停止。
npx wrangler r2 bucket create $BUCKET_NAME || true

echo "--- 步骤 5: 列出所有 R2 存储桶以供确认 ---"
npx wrangler r2 bucket list

echo "--- 步骤 6: 自动更新 wrangler.toml (直接替换，无备份) ---"
# 使用 sed 查找以 'bucket_name =' 开头的整行，并用新值替换。
# `^` 表示行首, `.*` 表示匹配该行余下的所有内容。
sed -i '' "s/^bucket_name = .*/bucket_name = \"$BUCKET_NAME\"/" wrangler.toml
sed -i '' "s/^name = .*/name = \"$PROJECT_NAME\"/" wrangler.toml
sed -i '' "s/^MAX_AGE = .*/MAX_AGE = \"$MAX_AGE\"/" wrangler.toml

echo "✅ wrangler.toml 已自动配置。"

echo "--- 步骤 7: 部署到 Cloudflare Pages ---"
npx wrangler pages deploy .

echo "--- 部署完成！---"

echo "--- 步骤 8: 查找生产域名 ---"
npx wrangler pages project list

echo "--- ✅ 自动化流程结束 ---"

# npx wrangler pages deployment tail
