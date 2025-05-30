# Release v1.0.0

## Release Date
2024-05-30

---

## 🚀 What's New
- Initial public release of Dify batch migration tool.
- Support for batch export/import of all apps between Dify environments.
- Auto read `.env` config, supports source/target URL, token, refresh token.
- Automatic refresh token on 401, compatible with Dify API response.
- Exported YAML format fully compatible with Dify import requirements.
- Pagination, backup, detailed logging, error handling, dry-run mode.
- Mac/Linux compatible, robust for large-scale migration.

## 🐞 Bug Fixes
- N/A (first release)

## 🛠 Improvements
- N/A (first release)

## 📚 Documentation
- Complete README in Chinese and English.
- Example scripts for export/import/refresh token.

## ⚠️ Compatibility & Breaking Changes
- Compatible with Dify >= 0.6.0 (API v1).
- No breaking changes.

---

## 💡 How to Upgrade / Use
1. Download release or pull latest code.
2. Configure `.env` as per `README.md`.
3. Grant execute permission: `chmod +x migrate-apps.sh`
4. Run migration: `./migrate-apps.sh`

---

## 🔔 Notes
- Test in staging before production.
- Backup data before migration.
- For token/YAML issues, see FAQ in docs.
- For help, submit issue or PR.

---

_本模板适用于 Dify 应用批量迁移工具的每次正式发布，可根据实际内容增删条目。_