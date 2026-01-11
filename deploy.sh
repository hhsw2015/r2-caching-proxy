#!/bin/bash

# 确保脚本在任何命令失败时立即退出
set -e

echo "--- 步骤 1: 登录 Cloudflare ---"
# 这一步必须在所有其他 wrangler 命令之前，以确保我们有权执行操作。
npx wrangler login

echo "--- 步骤 2: 解析输入参数以确定存储桶名称 ---"

# 检查用户是否提供了第一个参数（存储桶名称）
if [ -n "$1" ]; then
  # --- 场景 A: 用户提供了存储桶名称 ---
  BUCKET_NAME="$1"
  # 第二个参数作为缓存时间，如果不存在则使用默认值
  MAX_AGE=${2:-31536000}
  echo "✅ 使用命令行提供的存储桶名称: $BUCKET_NAME"
else
  # --- 场景 B: 用户未提供存储桶名称，启动自动检测 ---
  echo "🤖 未提供存储桶名称，启动自动检测..."

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
fi

# 根据最终确定的存储桶名称，生成项目名称
PROJECT_NAME="r2-proxy-$BUCKET_NAME"

echo "---"
echo "准备部署项目: $PROJECT_NAME"
echo "目标 R2 存储桶: $BUCKET_NAME"
echo "CDN 缓存时长: $MAX_AGE 秒"
echo ""

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

  echo ""
  echo "--- 步骤 8: 更新本地 template.yaml 文件 ---"
  if [ -f "template.yaml" ]; then
    echo "🔎 找到了 template.yaml 文件，正在更新 custom_host..."
    # 将 sed 命令写在单一行内，避免因换行符导致的解析错误。
    sed -i '' "s/^[[:space:]]*custom_host:.*/    custom_host: \"$PROJECT_DOMAIN\"/" template.yaml
    echo "✅ template.yaml 文件已更新。"

    cat template.yaml
  else
    echo "🤷 未找到 template.yaml 文件，跳过此步骤。"
  fi

else
  echo "⚠️ 无法自动提取项目域名。请手动在 Cloudflare 仪表板中查找项目 '$PROJECT_NAME' 的域名。"
fi

echo "--- ✅ 自动化流程结束 ---"

# npx wrangler pages deployment tail
