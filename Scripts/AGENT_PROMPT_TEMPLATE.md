# Шаблон задачи для агента (AppView)

Скопируйте в начало чата и заполните поля в `«…»`.

---

Исправь баг в `«AppView/… или AppViewServer/…»`.

**Контекст:** `«кратко: что ломается»`

**Сценарий:** `«hierarchy | tap | custom_info»`

**Эталон:** только точечный grep/ast-grep в baseline; baseline не редактировать и не удалять.

**Проверка (swift-only, default):** `bash AppView/Scripts/run_legacy_gates.sh` затем `«bash AppView/Scripts/verify_ui_hierarchy_mcp.sh»` (или tap / custom_info / wire_v2_ping). По умолчанию `SKIP_OBJC_BASELINE=1` — сравнение с golden в `AppView/Scripts/fixtures/`.

**Parity (если нужен ObjC diff):** `SKIP_OBJC_BASELINE=0` или `bash AppView/Scripts/verify_parity_nightly.sh`.

**Ответ:** только содержимое `appview-verify-logs/LATEST_SUMMARY.txt` (или `head -40` последнего `*-diff-*.txt`). Не открывать JSON, screenshots, DerivedData, полный xcodebuild.

---

## Быстрые команды (узкий stdout)

```bash
# Статические gates
bash AppView/Scripts/run_legacy_gates.sh

# После verify — только summary
cat appview-verify-logs/LATEST_SUMMARY.txt

# Или последний hierarchy diff
f=$(ls -t appview-verify-logs/ui_hierarchy-*-diff-*.txt 2>/dev/null | head -1)
grep '^RESULT:' "$f" && head -40 "$f"
```
