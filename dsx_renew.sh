#!/usr/bin/env bash
set -euo pipefail

NVIDIA_AIR_API_BASE="https://api.air-ngc.nvidia.com/api/v3"
NVIDIA_AIR_API_KEY="${NVIDIA_AIR_API_KEY:?必须设置 NVIDIA_AIR_API_KEY 环境变量}"
SIMULATION_ID="${SIMULATION_ID:?必须设置 SIMULATION_ID 环境变量}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"

should_retry() {
  case "$1" in
    000|429|500|502|503|504) return 0 ;;
    *) return 1 ;;
  esac
}

target_sleep_at="$(
python3 - <<'PY'
from datetime import datetime, timedelta, timezone
target = datetime.now(timezone.utc) + timedelta(hours=71)
print(target.replace(microsecond=0).isoformat().replace("+00:00", "Z"))
PY
)"

payload="$(mktemp)"
before_body="$(mktemp)"
after_body="$(mktemp)"
trap 'rm -f "$payload" "$before_body" "$after_body"' EXIT

printf '{"sleep_at":"%s"}' "$target_sleep_at" > "$payload"

simulation_url="${NVIDIA_AIR_API_BASE%/}/simulations/${SIMULATION_ID}/"

echo "target_sleep_at=$target_sleep_at"
echo "simulation_url=$simulation_url"

before_code=""
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  before_code="$(
  curl --ipv4 -sS -w '%{http_code}' \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'User-Agent: air-sdk/1.3.1' \
    -H 'X-Air-Sdk-Version: 1.3.1' \
    -H "Authorization: Bearer $NVIDIA_AIR_API_KEY" \
    -o "$before_body" \
    "$simulation_url"
  )" || before_code="000"

  echo "GET_attempt_${attempt}_http_code=$before_code"

  if [ "$before_code" = "200" ]; then
    break
  fi

  if [ "$attempt" -lt "$MAX_ATTEMPTS" ] && should_retry "$before_code"; then
    sleep_seconds=$((attempt * 10))
    echo "GET will retry in ${sleep_seconds}s"
    sleep "$sleep_seconds"
  else
    break
  fi
done

echo "before_http_code=$before_code"

if [ "$before_code" != "200" ]; then
  echo "GET failed: HTTP $before_code" >&2
  echo "response body:" >&2
  cat "$before_body" >&2
  echo >&2
  exit 1
fi

before_sleep_at="$(
python3 - "$before_body" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
print(data.get("sleep_at") or "")
PY
)"

echo "before_sleep_at=$before_sleep_at"

after_code=""
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  after_code="$(
  curl --ipv4 -sS -w '%{http_code}' -X PATCH \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'User-Agent: air-sdk/1.3.1' \
    -H 'X-Air-Sdk-Version: 1.3.1' \
    -H "Authorization: Bearer $NVIDIA_AIR_API_KEY" \
    --data @"$payload" \
    -o "$after_body" \
    "$simulation_url"
  )" || after_code="000"

  echo "PATCH_attempt_${attempt}_http_code=$after_code"

  if [ "$after_code" = "200" ]; then
    break
  fi

  if [ "$attempt" -lt "$MAX_ATTEMPTS" ] && should_retry "$after_code"; then
    sleep_seconds=$((attempt * 10))
    echo "PATCH will retry in ${sleep_seconds}s"
    sleep "$sleep_seconds"
  else
    break
  fi
done

echo "after_http_code=$after_code"

if [ "$after_code" != "200" ]; then
  echo "PATCH failed: HTTP $after_code" >&2
  echo "response body:" >&2
  cat "$after_body" >&2
  echo >&2
  exit 1
fi

after_sleep_at="$(
python3 - "$after_body" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
print(data.get("sleep_at") or "")
PY
)"

echo "after_sleep_at=$after_sleep_at"

if [ "$after_sleep_at" != "$target_sleep_at" ]; then
  echo "verify failed: expected=$target_sleep_at actual=$after_sleep_at" >&2
  echo "response body:" >&2
  cat "$after_body" >&2
  echo >&2
  exit 1
fi

echo "ok"