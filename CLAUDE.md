# CLAUDE.md

Hướng dẫn đầy đủ cho agent nằm ở AGENTS.md (import bên dưới) — đọc trước khi sửa code.

@AGENTS.md

## Tóm tắt nhanh

- Đây là **bản fork cá nhân** `heintruong/HyperMac`; `upstream` là repo gốc của tác giả.
- Build + cài đè `/Applications/HyperMac.app` + mở lại: `./build.sh`. Làm việc này **không cần hỏi** sau mỗi lần sửa build/test thành công. Không tự commit/push/tag/release.
- Test: xem lệnh `swift test` kèm cờ plugin ở mục 2 của AGENTS.md (máy chỉ có Command Line Tools).
- UI/log tiếng Việt, tên biến/hàm tiếng Anh; dùng token cỡ chữ/bo góc trong `Sources/Theme.swift`.
- Thêm lệnh vào helper root → tăng `HELPER_VERSION` trong `Resources/displaycontrol-power` **và** `PrivilegedHelper.requiredVersion`.
- Giữ nguyên ghi công bản quyền tác giả gốc (GPLv3).
