# Verify golden fixtures (swift-only mode)

Used when `SKIP_OBJC_BASELINE=1` (default for hierarchy/tap/custom_info verify).

| File | Script |
|------|--------|
| `ui-hierarchy-inspector-golden.norm` | `verify_ui_hierarchy_mcp.sh` |
| `tap-state-golden.txt` | `verify_ui_tap_mcp.sh` |
| `custominfo-baseline-golden.norm` | `verify_custom_info_client.sh` |

Regenerate hierarchy + tap from latest capture:

```bash
bash AppView/Scripts/update_golden_fixtures.sh [appview-verify-logs/tap-swift-YYYYMMDD-HHMMSS]
```
