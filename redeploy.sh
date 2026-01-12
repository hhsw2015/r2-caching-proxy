#!/bin/bash

# 确保脚本在任何命令失败时立即退出
set -e

echo "--- 步骤 1: 登录 Cloudflare ---"
# 这一步必须在所有其他 wrangler 命令之前，以确保我们有权执行操作。
npx wrangler login

echo "--- 步骤 2: 确定存储桶名称 ---"

# 运行 wrangler whoami 并用 awk 提取全小写的邮箱
USER_EMAIL=$(npx wrangler whoami | awk '/associated with the email/ { sub(/\.$/, "", $NF); print $NF }')
if [ -z "$USER_EMAIL" ]; then
  echo "❌ 错误: 无法从 'wrangler whoami' 的输出中提取邮箱。请重试。"
  exit 1
fi

# 从邮箱生成存储桶名称
BUCKET_NAME=${USER_EMAIL%@*}
# 在此场景下，第一个参数（如果存在）被视为缓存时间
MAX_AGE=${1:-31536000}
echo "✅ 成功自动检测并命名存储桶为: $BUCKET_NAME"

# 根据最终确定的存储桶名称，生成项目名称
PROJECT_NAME="r2-proxy-$BUCKET_NAME"

echo "---"
echo "准备部署项目: $PROJECT_NAME"
echo "目标 R2 存储桶: $BUCKET_NAME"
echo "CDN 缓存时长: $MAX_AGE 秒"
echo ""

echo "--- 步骤 6: 自动更新 wrangler.toml ---"
# 使用 sed 查找以 'bucket_name =' 开头的整行，并用新值替换。
# `^` 表示行首, `.*` 表示匹配该行余下的所有内容。

#CACHE_DOMAIN="cache.$BUCKET_NAME.de5.net"
CACHE_DOMAIN="cache.$BUCKET_NAME.indevs.in"

sed -i '' "s/^bucket_name = .*/bucket_name = \"$BUCKET_NAME\"/" wrangler.toml
sed -i '' "s/^name = .*/name = \"$PROJECT_NAME\"/" wrangler.toml
sed -i '' "s/^MAX_AGE = .*/MAX_AGE = \"$MAX_AGE\"/" wrangler.toml
sed -i '' "s/^R2_CUSTOM_DOMAIN = .*/R2_CUSTOM_DOMAIN = \"$CACHE_DOMAIN\"/" wrangler.toml

echo "✅ wrangler.toml 已自动配置。"
cat wrangler.toml

echo "--- 步骤 7: 部署到 Cloudflare Pages ---"
npx wrangler pages deploy .

echo "--- 部署完成！---"

echo "--- 步骤 8: 查找生产域名 ---"
#npx wrangler pages project list

PROJECT_DOMAIN=$(npx wrangler pages project list | grep "$PROJECT_NAME" | awk -F '│' '{print $3}' | sed 's/ //g')

if [ -n "$PROJECT_DOMAIN" ]; then
  echo "🎉 您的 Pages 项目已成功部署！访问地址:"
  echo "   ➡️  https://$PROJECT_DOMAIN"

else
  echo "⚠️ 无法自动提取项目域名。请手动在 Cloudflare 仪表板中查找项目 '$PROJECT_NAME' 的域名。"
fi

echo "--- ✅ 自动化流程结束 ---"

# npx wrangler pages deployment tail
