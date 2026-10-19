#!/usr/bin/env bash
# Quick check: iOS AppViewServer MCP setHidden on UIView (no mac UI).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/AppView/Scripts/appview_dismiss_dialogs.sh"

OID="${1:-13}"
appview_ios_mcp_curl "/status" >/dev/null || {
  echo "FAIL: iOS MCP :47190 not reachable. Launch AppViewCustomInfoDemo with MCP subspec." >&2
  exit 1
}

before="$(appview_ios_mcp_curl "/hierarchy" | python3 -c "
import json,sys
oid=int(sys.argv[1])
d=json.load(sys.stdin)['data']['items']

def find(items):
  for it in items:
    if it['oid']==oid: return it.get('hidden', False)
    f=find(it.get('children',[]) or [])
    if f is not None: return f
  return None
print(find(d))
" "$OID")"

curl -sf --max-time 5 -X POST "http://127.0.0.1:47190/view/${OID}/attributes" \
  -H "Content-Type: application/json" \
  -d '{"setterSelector":"setHidden:","attrType":14,"value":true}' >/dev/null

after="$(appview_ios_mcp_curl "/hierarchy" | python3 -c "
import json,sys
oid=int(sys.argv[1])
d=json.load(sys.stdin)['data']['items']

def find(items):
  for it in items:
    if it['oid']==oid: return it.get('hidden', False)
    f=find(it.get('children',[]) or [])
    if f is not None: return f
  return None
print(find(d))
" "$OID")"

curl -sf --max-time 5 -X POST "http://127.0.0.1:47190/view/${OID}/attributes" \
  -H "Content-Type: application/json" \
  -d '{"setterSelector":"setHidden:","attrType":14,"value":false}' >/dev/null

echo "oid=$OID hidden before=$before after_toggle=$after"
if [[ "$after" == "True" ]]; then
  echo "RESULT: PASS — iOS MCP setHidden toggled hidden flag"
  exit 0
fi
echo "RESULT: FAIL — hidden flag did not change" >&2
exit 1
