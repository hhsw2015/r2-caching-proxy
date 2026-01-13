echo "--- 生成 s3-balance 配置预览 ---"
CONFIG_JSON="config.json"
BUCKET_YAML="template.yaml"

if ! command -v yq >/dev/null 2>&1; then
  echo "❌ 未检测到 yq，请先安装后再运行该步骤。"
  echo "   macOS: brew install yq"
  echo "   其他: https://github.com/mikefarah/yq"
else
  if [ ! -f "$CONFIG_JSON" ]; then
    echo "❌ 未找到 $CONFIG_JSON，无法更新 s3-balance 配置。"
  elif [ ! -f "$BUCKET_YAML" ]; then
    echo "❌ 未找到 $BUCKET_YAML，无法更新 s3-balance 配置。"
  else
    TMP_CONFIG="$(mktemp)"
    BUCKET_JSON="$(mktemp)"

    yq -o=json '.' "$BUCKET_YAML" >"$BUCKET_JSON"

    BUCKET_JSON_PATH="$BUCKET_JSON" TMP_CONFIG_PATH="$TMP_CONFIG" python3 - <<'PY'
import json, re, os
cfg = json.load(open("config.json"))
bucket_data = json.load(open(os.environ["BUCKET_JSON_PATH"]))
bucket = bucket_data[0] if isinstance(bucket_data, list) and bucket_data else bucket_data
buckets = cfg.get("buckets", [])
idx = next((i for i, b in enumerate(buckets) if b.get("name") == bucket.get("name")), None)
new_bucket = idx is None
if new_bucket:
  s3_idx = next((i for i, b in enumerate(buckets) if b.get("name") == "s3-balance"), None)
  if s3_idx is None:
    buckets.append(bucket)
  else:
    buckets.insert(s3_idx, bucket)
else:
  buckets[idx] = bucket
cfg["buckets"] = buckets
if new_bucket:
  for b in buckets:
    if b.get("name") == "s3-balance":
      m = re.match(r"^(\d+)GB$", str(b.get("max_size", "")).strip(), re.I)
      if m:
        b["max_size"] = f"{int(m.group(1)) + 10}GB"
      break
json.dump(cfg, open(os.environ["TMP_CONFIG_PATH"], "w"), indent=2, ensure_ascii=True)
open(os.environ["TMP_CONFIG_PATH"], "a").write("\n")
PY

    echo "✅ 已生成配置预览: $TMP_CONFIG"
    read -r -p "是否查看配置预览? [y/N]: " PREVIEW_CONFIRM
    if [[ "$PREVIEW_CONFIRM" =~ ^[Yy]$ ]]; then
      echo "--- 预览: 将被更新的 buckets ---"
      BUCKET_JSON_PATH="$BUCKET_JSON" TMP_CONFIG_PATH="$TMP_CONFIG" python3 - <<'PY'
import json, os
cfg = json.load(open(os.environ["TMP_CONFIG_PATH"]))
bucket_data = json.load(open(os.environ["BUCKET_JSON_PATH"]))
bucket = bucket_data[0] if isinstance(bucket_data, list) and bucket_data else bucket_data
name = bucket.get("name")
show = [b for b in cfg.get("buckets", []) if b.get("name") in (name, "s3-balance")]
print(json.dumps(show, indent=2, ensure_ascii=True))
PY
    fi
  fi
fi

if [ -f "$TMP_CONFIG" ]; then
  echo "--- 步骤 10: 是否写入并导入到 s3-balance ---"
  read -r -p "是否将新配置写入 config.json 并导入到 s3-balance? [y/N]: " IMPORT_CONFIRM
  if [[ "$IMPORT_CONFIRM" =~ ^[Yy]$ ]]; then
    mv "$TMP_CONFIG" "$CONFIG_JSON"
    rm -f "$BUCKET_JSON"

    API_URL="${S3_BALANCE_URL:-}"
    if [ -z "$API_URL" ]; then
      read -r -p "请输入 s3-balance 域名/地址 (需包含 https://，不带 /api/config): " API_URL
    fi
    API_URL="${API_URL%/}/api/config"
    API_TOKEN=$(
      python3 - <<'PY'
import json
cfg = json.load(open("config.json"))
print(cfg.get("api", {}).get("token", ""))
PY
    )
    if [ -z "$API_TOKEN" ]; then
      read -r -s -p "请输入 s3-balance API token: " API_TOKEN
      echo ""
    fi

    API_PAYLOAD="$(mktemp)"
    API_PAYLOAD_PATH="$API_PAYLOAD" python3 - <<'PY'
import json, os

def to_duration_ns(value):
  if isinstance(value, (int, float)):
    return int(value)
  if not isinstance(value, str):
    return value
  s = value.strip()
  try:
    return int(s)
  except ValueError:
    pass
  units = {"ns": 1, "us": 1000, "ms": 1000000, "s": 1000000000, "m": 60000000000, "h": 3600000000000}
  for suffix, mult in units.items():
    if s.endswith(suffix):
      num = s[: -len(suffix)]
      try:
        return int(float(num) * mult)
      except ValueError:
        return value
  return value

def convert(obj, key_map=None):
  if isinstance(obj, list):
    return [convert(i, key_map) for i in obj]
  if not isinstance(obj, dict):
    return obj
  out = {}
  for k, v in obj.items():
    nk = key_map.get(k, k) if key_map else k
    nested_map = NESTED_MAP.get(nk)
    out[nk] = convert(v, nested_map)
  return out

ROOT_MAP = {
  "server": "Server",
  "database": "Database",
  "buckets": "Buckets",
  "balancer": "Balancer",
  "metrics": "Metrics",
  "s3api": "S3API",
  "api": "API",
}
SERVER_MAP = {
  "host": "Host",
  "port": "Port",
  "read_timeout": "ReadTimeout",
  "write_timeout": "WriteTimeout",
  "idle_timeout": "IdleTimeout",
}
DATABASE_MAP = {
  "type": "Type",
  "dsn": "DSN",
  "max_open_conns": "MaxOpenConns",
  "max_idle_conns": "MaxIdleConns",
  "conn_max_lifetime": "ConnMaxLifetime",
  "log_level": "LogLevel",
  "auto_migrate": "AutoMigrate",
}
BUCKET_MAP = {
  "name": "Name",
  "endpoint": "Endpoint",
  "region": "Region",
  "access_key_id": "AccessKeyID",
  "secret_access_key": "SecretAccessKey",
  "max_size": "MaxSize",
  "weight": "Weight",
  "enabled": "Enabled",
  "path_style": "PathStyle",
  "virtual": "Virtual",
  "custom_host": "CustomHost",
  "remove_bucket": "RemoveBucket",
  "operation_limits": "OperationLimits",
}
OP_LIMITS_MAP = {
  "type_a": "TypeA",
  "type_b": "TypeB",
}
BALANCER_MAP = {
  "strategy": "Strategy",
  "health_check_period": "HealthCheckPeriod",
  "update_stats_period": "UpdateStatsPeriod",
  "retry_attempts": "RetryAttempts",
  "retry_delay": "RetryDelay",
}
METRICS_MAP = {
  "enabled": "Enabled",
  "path": "Path",
  "token": "Token",
}
S3API_MAP = {
  "access_key": "AccessKey",
  "secret_key": "SecretKey",
  "virtual_host": "VirtualHost",
  "proxy_mode": "ProxyMode",
  "auth_required": "AuthRequired",
  "host": "Host",
}
API_MAP = {
  "enabled": "Enabled",
  "token": "Token",
}

NESTED_MAP = {
  "Server": SERVER_MAP,
  "Database": DATABASE_MAP,
  "Buckets": BUCKET_MAP,
  "OperationLimits": OP_LIMITS_MAP,
  "Balancer": BALANCER_MAP,
  "Metrics": METRICS_MAP,
  "S3API": S3API_MAP,
  "API": API_MAP,
}

cfg = json.load(open("config.json"))
converted = convert(cfg, ROOT_MAP)
if "Buckets" in converted:
  converted["Buckets"] = [convert(b, BUCKET_MAP) for b in converted["Buckets"]]
  for b in converted["Buckets"]:
    if "OperationLimits" in b:
      b["OperationLimits"] = convert(b["OperationLimits"], OP_LIMITS_MAP)
  orig = {b.get("name"): b for b in cfg.get("buckets", []) if isinstance(b, dict)}
  for b in converted["Buckets"]:
    src = orig.get(b.get("Name"))
    if not src:
      continue
    if "custom_host" in src and "CustomHost" not in b:
      b["CustomHost"] = src["custom_host"]
    if "remove_bucket" in src and "RemoveBucket" not in b:
      b["RemoveBucket"] = src["remove_bucket"]

if "Server" in converted:
  for k in ("ReadTimeout", "WriteTimeout", "IdleTimeout"):
    if k in converted["Server"]:
      converted["Server"][k] = to_duration_ns(converted["Server"][k])
if "Balancer" in converted:
  for k in ("HealthCheckPeriod", "UpdateStatsPeriod", "RetryDelay"):
    if k in converted["Balancer"]:
      converted["Balancer"][k] = to_duration_ns(converted["Balancer"][k])

json.dump(converted, open(os.environ["API_PAYLOAD_PATH"], "w"), indent=2, ensure_ascii=True)
open(os.environ["API_PAYLOAD_PATH"], "a").write("\n")
PY

    curl -X POST "$API_URL" \
      -H "Authorization: Bearer $API_TOKEN" \
      -H "Content-Type: application/json" \
      -d @"$API_PAYLOAD"
  else
    echo "⏭️ 已跳过写入与导入 s3-balance。"
    rm -f "$TMP_CONFIG" "$BUCKET_JSON"
  fi
fi
