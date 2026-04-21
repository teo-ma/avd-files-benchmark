#!/usr/bin/env bash
# 从 macOS / Linux 远程触发 Azure VM 上的 Run-Benchmark.ps1
# 用法：
#   export AZ_RG=rg-avd-haier-20260312
#   export AZ_VM=avd-gpu-u6
#   export SA=stavdhaieru6h01
#   export SHARE=share1tb
#   export KEY="$(az storage account keys list -g $AZ_RG -n $SA --query '[0].value' -o tsv)"
#   ./scripts/invoke-remote-benchmark.sh
#
# 也可用命令行参数：
#   ./scripts/invoke-remote-benchmark.sh <RG> <VM> <SA> <SHARE> [KEY]

set -euo pipefail

RG="${1:-${AZ_RG:-}}"
VM="${2:-${AZ_VM:-}}"
SA="${3:-${SA:-}}"
SHARE="${4:-${SHARE:-}}"
KEY="${5:-${KEY:-}}"

if [[ -z "$RG" || -z "$VM" || -z "$SA" || -z "$SHARE" ]]; then
  echo "Usage: $0 <RG> <VM> <StorageAccount> <ShareName> [Key]" >&2
  exit 2
fi
if [[ -z "$KEY" ]]; then
  KEY="$(az storage account keys list -g "$RG" -n "$SA" --query '[0].value' -o tsv)"
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/Run-Benchmark.ps1"
BAKED="/tmp/Run-Benchmark-baked-$$.ps1"

# 将 Key 烘入 here-string，避开 az run-command --parameters 在特殊字符 (+,=,/) 上的解析问题
python3 - "$SRC" "$SA" "$SHARE" "$KEY" "$BAKED" <<'PY'
import re, sys
src_path, sa, share, key, out_path = sys.argv[1:]
src = open(src_path).read()
m = re.search(r'param\(\s*\n.*?\)\s*\n', src, re.DOTALL)
assert m, 'no param block found in Run-Benchmark.ps1'
injected = (
    f"$StorageAccount = '{sa}'\n"
    f"$ShareName = '{share}'\n"
    f"$AccountKey = @'\n{key}\n'@\n"
    "$AccountKey = $AccountKey.Trim()\n"
    "$DriveLetter = 'T:'\n"
    "$ResultFile = ''\n"
)
open(out_path, 'w').write(src[:m.start()] + injected + src[m.end():])
PY

OUT="/tmp/benchmark-$(date +%Y%m%d-%H%M%S)-${VM}.json"
echo "Invoking benchmark on $VM (output -> $OUT) ..."
az vm run-command invoke -g "$RG" -n "$VM" \
  --command-id RunPowerShellScript \
  --scripts @"$BAKED" \
  -o json > "$OUT"

echo "=== StdOut ==="
python3 -c "
import json,sys
d=json.load(open('$OUT'))
for v in d['value']:
    print('---', v['code'], '---')
    print(v['message'])
"
rm -f "$BAKED"
echo "Saved raw response to $OUT"
