# AGENTS.md — HyperMac (DisplayControl)

> Tài liệu dành cho AI coding agent (Claude Code, Cursor…) đọc trước khi chỉnh sửa dự án. Cập nhật lần cuối: **2026-11-23 (fork từ v1.9.8)**.

## 1. Tổng quan

- **HyperMac** là app menu bar thuần Swift cho macOS 14+ (Apple Silicon), dùng SwiftPM + AppKit + SwiftUI.
- **Bản fork cá nhân:** `heintruong/HyperMac` (remote `origin`), bản gốc `mrgoose000000-gif/HyperMac` (remote `upstream`). Kéo bản mới của tác giả: `git fetch upstream && git merge upstream/main`.
- Đã gỡ khỏi fork: bảng kích hoạt (mã Zalo), nút/bảng Donate, nút "Tác giả", ảnh QR; **khóa sạc 80% / sạc đầy tạm thời / hiệu chuẩn pin** (dùng giới hạn sạc có sẵn của macOS thay thế; helper không còn lệnh `charge-*`/`status`). Giữ nguyên ghi công bản quyền gốc (bắt buộc theo GPLv3).
- Đã thêm ở fork: **Gập máy vẫn chạy**, **Xếp chồng cửa sổ (cascade)** và **Vuốt 3 ngón để chuyển cửa sổ** — xem mục 10.
- Bundle ID: `com.opensource.hypermac`, tên app: `HyperMac`, chạy ẩn Dock (`LSUIElement`).
- Tính năng: chia cửa sổ (Rectangle) + xếp chồng cascade, AltTab, lịch sử Clipboard, cắt/dán Finder, thông tin pin + Sleep Guard, độ sáng/độ phân giải/màn ảo, chống sleep + gập máy vẫn chạy, nhiệt độ/quạt/CPU-RAM-GPU, tốc độ ổ đĩa, chụp màn hình có chú thích, ẩn icon menu bar, dọn rác/gỡ app.
- **Fan Control:** đã gỡ ở v1.5.2, được người dùng yêu cầu thêm lại (bản đơn giản kiểu iStat Menus: System / Medium / High + thanh trượt %). Xem mục 9. Không mở rộng thêm (rules editor, curve…) trừ khi người dùng yêu cầu.

## 2. Build & kiểm tra

```bash
# Chỉ biên dịch (không cài, không kill app đang chạy)
swift build -c release

# Build + đóng gói .app + .zip, KHÔNG cài vào /Applications
./build.sh --no-run

# Build + cài /Applications + chạy (sẽ pkill HyperMac trước)
./build.sh
```

- **Quy ước của chủ fork:** Sau mỗi lần sửa và build/test thành công, **luôn cài đè `/Applications/HyperMac.app` và mở lại (`./build.sh`) để test ngay, không cần hỏi lại.** `build.sh` đóng app êm trước (để chạy cleanup pin/quạt/gập máy), chỉ `kill -9` nếu app không chịu thoát. Quyền này **không** bao gồm commit/push/tag/GitHub Release — vẫn chờ lệnh riêng.
- **Chạy test** (máy chỉ có Command Line Tools, không có Xcode → phải trỏ plugin swift-testing):

```bash
CLT=/Library/Developer/CommandLineTools
swift test -Xswiftc -plugin-path -Xswiftc $CLT/usr/lib/swift/host/plugins/testing \
  -Xswiftc -F -Xswiftc $CLT/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $CLT/Library/Developer/Frameworks
```

- `xcodebuild` không bắt buộc; máy hiện tại chỉ có Command Line Tools và build bằng SwiftPM.
- Log runtime: `/tmp/displaycontrol.log` (hàm `appLog()` trong `Sources/Logger.swift`).
- App đang chạy: `pgrep -xl HyperMac`.
- **Chữ ký code:** dùng identity self-signed cố định `HyperMac Self-Signed`
  (tạo bởi `./scripts/setup-signing-identity.sh`). Tuyệt đối không quay lại
  `codesign -s -` (ad-hoc) vì mỗi lần build sẽ sinh cdhash mới và macOS thu hồi
  quyền Accessibility → `⌘Tab` / `⌘⇧C` chết. Xem mục 7.

## 3. Bản đồ mã nguồn

| File | Vai trò |
|---|---|
| `Sources/AppMain.swift` | Entry point, `AppDelegate`, menu bar status item, popover |
| `Sources/Views.swift` | Toàn bộ UI SwiftUI (main popover, settings, pin, display, thermal) |
| `Sources/WindowManager.swift` | AltTab: liệt kê cửa sổ AX/CG, HUD, MRU, chụp thumbnail nền |
| `Sources/WindowSnapManager.swift` | Chia cửa sổ & chuyển màn hình |
| `Sources/KeyInterceptor.swift` | CGEventTap toàn cục: phím tắt, media keys, clipboard HUD keys |
| `Sources/AccessibilityRecovery.swift` | Tự reset + prompt lại quyền Accessibility sau update |
| `Sources/ClipboardManager.swift` | Lịch sử clipboard, giới hạn lưu, retention, HUD panel |
| `Sources/ClipboardOverlayView.swift` | UI bảng Clipboard HUD |
| `Sources/AltTabOverlayView.swift` | UI HUD AltTab |
| `Sources/ThermalManager.swift` | Đọc nhiệt độ HID/PMU + trạng thái thermal (KHÔNG điều khiển quạt) |
| `Sources/FanManager.swift` | Điều khiển quạt: đọc RPM qua `smc`, ghi qua helper, an toàn 90°C / thoát / ngủ |
| `Sources/FanControlCardView.swift` | Thẻ Quạt trong tab Nhiệt độ & Cảm biến (ẩn nếu máy không có quạt) |
| `Sources/DiskSpeedManager.swift` | Đo tốc độ đọc/ghi ổ vật lý (IOKit), interface LAN cho NAS, I/O theo tiến trình |
| `Sources/BatteryManager.swift` | Thông tin pin, cảnh báo, Sleep Guard, kiểm tra/cài helper root |
| `Sources/DisplayManager.swift` | Độ sáng, DDC/CI, màn hình ảo |
| `Sources/VirtualDisplayManager.swift` + `VirtualDisplayBridge/` | Cầu nối Objective-C cho màn hình ảo |
| `Sources/CaffeinateManager.swift` | Chống sleep màn hình |
| `Sources/UpdateManager.swift` | Kiểm tra/tải bản cập nhật; repo ở `UpdateManager.repo` (= fork), fallback `version.json` nhánh `main` |
| `Sources/ShortcutManager.swift` + `ShortcutSettingsView.swift` | Danh sách `ShortcutAction`, phím mặc định, lưu/đổi phím tắt, `perform()` điều phối hành động |
| `Sources/PrivilegedHelper.swift` | Đường dẫn helper root + `requiredVersion` |
| `Resources/displaycontrol-power` | Helper root (bash): sạc, quạt, `sleep-disable`; cài bằng `install-helper.sh` |
| `Sources/ShellHelper.swift` | `shell()` đồng bộ + tìm binary Homebrew |

## 4. Quy ước

- UI và log dùng **tiếng Việt**; tên biến/hàm dùng tiếng Anh.
- **Style UI:** dùng token trong `Sources/Theme.swift`: cỡ chữ `FS.caption(10) / label(11) / body(12) / title(13) / subhead(14) / value(16) / display(22)…`, bo góc `Rad.sm(6) / md(10) / lg(14)`. Không dùng số cỡ chữ lẻ (7.5, 8.5…) và không chữ < 10pt. Đậm (`.bold`) chỉ cho số lớn (>= `FS.value`); còn lại dùng `.semibold`/`.medium`.
- `@MainActor` cho các manager; cập nhật state UI phải trên main thread.
- Tránh chạy `Process`/`shell()` nặng trên main thread (gây khựng popover).
- Lưu cài đặt qua `UserDefaults` với key có tiền tố rõ ràng (`clipboard_*`, `fan_*` cũ đã bỏ, `show_menubar_thermal`…).
- Không hardcode đường dẫn tuyệt đối của máy dev (ví dụ `/Users/<tên>/...`).
- Giữ `Package.swift` ở `swift-tools-version: 5.9` (Swift 5 language mode) để tránh lỗi concurrency nghiêm ngặt.
- **Không tự tạo tag/release hay push bản phát hành** khi chưa được người dùng xác nhận rõ ràng. Cứ build local, test xong, chờ lệnh.

## 5. Ghi chú kỹ thuật

### 5.1. Đo tốc độ chép file — `Sources/DiskSpeedManager.swift`
- UI: `FileTransferSpeedCard` trong `HardwareCareTabView`, đặt ngay dưới thanh chọn
  Pin / Nhiệt độ (luôn hiển thị, không phụ thuộc segment đang chọn).
- **Mặc định TẮT**: người dùng bật bằng switch trên card (lưu ở
  `UserDefaults["disk_speed_enabled"]`). Khi tắt, không có timer, không quét ổ/tiến
  trình, không cấp phát bộ đếm.
- **Chỉ chạy khi popover mở**: `AppDelegate` là `NSPopoverDelegate`; `popoverDidShow`
  → `setPopoverVisible(true)`, `popoverDidClose` → `setPopoverVisible(false)`.
  Đóng bảng là dừng timer + `sampler.reset()` + xoá số liệu đã publish.
- Kiến trúc: `DiskSpeedManager` (`@MainActor`, `ObservableObject`) giữ `Timer` 1s trên
  main run loop; mỗi tick đẩy `DiskSpeedSampler.sample()` sang `DispatchQueue` nền.
  Sampler tính delta byte / delta thời gian (`max(0.25s, …)`) → MB/s.

**Ổ vật lý (chính xác):**
- Duyệt `IOMedia` có `Whole = true`, lấy **cha trực tiếp**; chỉ nhận khi class cha là
  `IOBlockStorageDriver` (nơi có property `Statistics`).
- `AppleAPFSContainerScheme` cũng có `Statistics` riêng → nếu không lọc theo class
  cha, tốc độ sẽ bị cộng trùng (gấp đôi) giữa `disk0` và `disk3`.
- Bỏ qua media ảo của file `.dmg/.iso` (IORegistry name chứa `Disk Image`) để ổ
  "Tor Browser"… không xuất hiện như ổ cứng thật.
- Tên hiển thị: đi ngược cây IORegistry từ volume đang mount (`getmntinfo`) lên tới
  IOMedia vật lý (`mediaEntry(forBSDName:)`), chọn volume gốc `/` hoặc volume lớn
  nhất. Fallback: `Device Characteristics → Product Name` (`APPLE SSD…` →
  `SSD nội bộ`), cuối cùng là BSD name.
- Dòng chi tiết trong card hiển thị **nguồn → đích** (ổ đọc nhiều nhất → ổ ghi nhiều
  nhất), ví dụ `U280-Pro → SSD nội bộ`; nếu cùng một ổ thì chỉ hiện tên ổ.

**NAS / ổ mạng (xấp xỉ):**
- `networkVolumeHosts()` lấy host từ `getmntinfo` (`//user@host/share`, `host:/path`).
- `route -n get <host>` (cache 60s) → tên interface (`en0`, `en1`, …).
- Đọc byte counter 64-bit của interface qua `sysctl` MIB
  `[CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]` (`if_msghdr2.ifm_data`).
- Nếu không resolve được interface: cộng các interface `en*`/`ppp*`.
- Đây là tốc độ **của card mạng**, không phải riêng phiên SMB → có thể lẫn traffic khác.

**Tiến trình đang chép:**
- `proc_listallpids` + `proc_pid_rusage(pid, RUSAGE_INFO_V4)` lấy
  `ri_diskio_bytesread/written`; lưu counter của frame trước để tính delta.
- Chỉ gắn tên tiến trình khi `peak >= 3 MB/s` **và** `peak >= 50%` tổng lưu lượng,
  nếu không sẽ hiện nhầm I/O nền (Spotlight, `BackgroundShortcutRunner`).
- Hạn chế đã biết: ghi qua page cache có thể xong trước nhịp lấy mẫu nên tiến trình
  có thể không hiện (ví dụ `dd` tốc độ cao); số liệu ổ cứng vẫn đúng.

**Debug:** đặt `HYPERMAC_DISKSPEED_DEBUG=1` để log mỗi mẫu vào `/tmp/displaycontrol.log`
(dòng `💾 DiskSpeed: …`). Hook `HYPERMAC_DISKSPEED_TEST_HOST` đã được gỡ.

### 5.2. Kiểm thử giao diện không cần chụp màn hình
- `HYPERMAC_PREVIEW=1` mở cửa sổ 380×570 chứa `MainView` (không tạo status item).
- `HYPERMAC_PREVIEW_TAB=0|1|2` chọn tab (mặc định 1).
- `HYPERMAC_PREVIEW_OUT=/tmp/ui.png` render thẳng ra PNG bằng `ImageRenderer`
  rồi thoát — hữu ích khi terminal không có quyền Screen Recording.
- `HYPERMAC_DISKSPEED_FAKE=1` nạp số liệu giả (U280-Pro → SSD, LAN en0) để kiểm tra
  layout dòng chi tiết. **Chỉ dùng khi phát triển**, không ảnh hưởng người dùng.
- `HYPERMAC_DISKSPEED_AUTOSTART=1` giả lập popover đang mở lúc khởi động;
  `HYPERMAC_DISKSPEED_AUTOCLOSE=<giây>` tự đóng sau N giây — dùng để kiểm tra
  timer bật/tắt mà không cần bấm menu bar.
- Lưu ý: `ImageRenderer` không render nội dung bên trong `ScrollView`, nên ảnh
  preview chỉ dùng để kiểm tra phần header/tab/card, không thay thế kiểm thử thật.

## 7. Chứng chỉ ký cố định (bắt buộc cho TCC)

**Vấn đề:** ký ad-hoc (`codesign -s -`) khiến cdhash đổi sau mỗi lần build →
macOS coi là app khác → **thu hồi quyền Accessibility** → `⌘Tab`, `⌘⇧C` không chạy
cho tới khi người dùng cấp lại tay.

**Giải pháp đã áp dụng:** chứng chỉ self-signed cố định `HyperMac Self-Signed`, sinh **trên máy chủ fork** (key nằm ở `~/.hypermac-signing/`, không liên quan chứng chỉ của tác giả gốc).

```bash
./scripts/setup-signing-identity.sh   # chạy 1 lần
./build.sh                            # build.sh tự dùng identity này
```

- Script sinh key + cert (EKU `codeSigning`) trong `~/.hypermac-signing/` (mode 700),
  import vào login keychain, rồi thêm trust policy Code Signing ở user domain.
- `build.sh` tự dò identity; nếu có thì ký bằng nó, nếu không thì fallback ad-hoc
  (kèm cảnh báo). Có thể override bằng biến môi trường `HYPERMAC_SIGN_IDENTITY`.
- Designated Requirement (`codesign -d -r-`) có dạng
  `identifier "com.opensource.hypermac" and certificate root = H"…"`
  → **không phụ thuộc nội dung binary**, nên quyền TCC giữ nguyên qua mọi rebuild.

**Nếu vẫn mất quyền / app không nhận phím tắt:**

```bash
# 1. Kiểm tra chữ ký
codesign -dv --verbose=4 /Applications/HyperMac.app | grep Authority
# 2. Xoá entry TCC cũ rồi mở lại app để prompt
tccutil reset Accessibility com.opensource.hypermac
open /Applications/HyperMac.app
# 3. System Settings → Privacy & Security → Accessibility → bật HyperMac
```

**Không commit** `~/.hypermac-signing/` hay file `.p12` vào repo (chứa private key).
`.gitignore` đã chặn `*.p12` và `*.p12.base64`.

### 7.1. Ký bản phát hành trên GitHub Actions

Runner không có keychain của máy dev, nên phải đưa private key vào **GitHub Secrets**:

1. Xuất chứng chỉ (giữ nguyên key/cert cũ để root hash không đổi):

```bash
./scripts/export-ci-signing.sh
# → ~/.hypermac-signing/ci-signing.p12
# → ~/.hypermac-signing/ci-signing.p12.base64
# → in ra mật khẩu + certificate root SHA-1
```

2. Thêm 2 secret tại `Settings → Secrets and variables → Actions`:
   - `HYPERMAC_SIGNING_P12_BASE64`: nội dung file `.base64`
   - `HYPERMAC_SIGNING_P12_PASSWORD`: mật khẩu script in ra

3. Workflow `.github/workflows/release.yml` sẽ:
   - tạo keychain tạm, import `.p12`, mở partition list cho `codesign`,
   - **thêm keychain tạm vào search list** của user (codesign chỉ tìm identity
     trong các keychain thuộc search list; `--keychain` một mình là không đủ),
   - build với `HYPERMAC_SIGN_IDENTITY=HyperMac Self-Signed` và
     `HYPERMAC_SIGN_KEYCHAIN=<keychain tạm>`,
   - verify `Authority=HyperMac Self-Signed` + in DR,
   - xoá keychain tạm ở bước `always()`.

Nếu thiếu secret, workflow vẫn build nhưng **fallback ad-hoc** (kèm cảnh báo) —
khi đó quyền Accessibility sẽ mất sau update.

**Ba cái bẫy đã gặp thật (đừng sửa lại thành sai):**

- **p12 phải là định dạng legacy.** OpenSSL 3 mặc định xuất MAC SHA-256 + AES/PBES2;
  `security import` trên runner macOS 14 báo
  `MAC verification failed during PKCS12 import (wrong password?)` dù mật khẩu đúng.
  `scripts/export-ci-signing.sh` dùng `openssl pkcs12 -export -legacy` (SHA-1 + 3DES).
- **Không dùng `security find-identity -v`.** Cờ `-v` chỉ liệt kê identity *đã trust*;
  cert tự ký trên runner là untrusted nên `-v` trả 0 identity dù `codesign` ký được.
  `build.sh` và workflow đều dùng `find-identity -p codesigning` (không `-v`).
- **Không dùng `base64 --decode`.** `base64` của macOS 14 chỉ có `-D`; thậm chí secret
  có thể lẫn CRLF. Workflow strip whitespace rồi decode bằng `python3`, fallback
  `openssl base64 -d -A`, cuối cùng mới `base64 -D`, và tự nhận diện secret bị base64
  2 lớp.

**Lưu ý quan trọng:**
- Chuyển từ bản của tác giả sang bản fork tự ký: DR đổi nên quyền Accessibility/Screen
  Recording mất **một lần**; từ đó giữ nguyên.
- Không bao giờ tạo lại cert/key (root hash đổi → mất quyền của mọi người).
  Cert hiện có hạn 10 năm (`-days 3650`).
- Secret chứa private key: nếu repo bị xâm nhập, key có thể bị lộ → phải tạo cert
  mới và chấp nhận mất quyền một lần. Xem mục 7.3.

### 7.2. Tự khôi phục quyền sau update — `Sources/AccessibilityRecovery.swift`

- Gọi trong `applicationDidFinishLaunching` **trước** `KeyInterceptor.shared.start()`.
- Mỗi lần khởi động, nếu `AXIsProcessTrusted() == false` **và**
  `UserDefaults["ax_recovery_version"] != phiên bản hiện tại`:
  - chạy `tccutil reset Accessibility com.opensource.hypermac` (xoá entry cũ bị kẹt),
  - lưu `ax_recovery_version` = phiên bản hiện tại (mỗi bản chỉ reset **một lần**,
    nên không lặp lại mỗi lần mở app và không phiền người dùng đã từ chối cấp quyền),
  - sau 0.8s gọi `AXIsProcessTrustedWithOptions(prompt: true)` để macOS hiện hộp
    thoại cấp lại.
- Không cần cờ "từng được cấp quyền": entry TCC bị kẹt sau update thường vẫn hiện
  trong System Settings nên không thể phân biệt bằng `UserDefaults`.
- Người dùng chỉ cần bật switch trong System Settings, **không phải xoá app và thêm lại**.
- `tccutil` chỉ reset được khi app có bundle ID hợp lệ; nếu không có, hàm bỏ qua im lặng.


## 8. Ghi chú kiểm thử

- Máy không có quạt (MacBook Air): `smc -f` trả `Total fans in system: 0`, thẻ Quạt tự ẩn.
- Kiểm tra nhanh sau khi sửa:
  1. `⌘ + Tab` phải hiện HUD gần như tức thì (< ~100ms), thumbnail xuất hiện sau.
  2. `⌘ + ⇧ + C` mở Clipboard; thử `1–9`, `↑↓`, `↵`, `⌥P`, `⌥⌫`, `⎋`.
  3. Settings → Clipboard: chọn 500/∞, đổi "Tự động xoá", bấm "Dọn ngay".
  4. Tab nhiệt độ: thẻ Quạt (System / Medium / High / thanh trượt) + nhiệt độ, cảm biến, pill Menu Bar. Xem mục 9.5 để kiểm thử quạt.
  5. Ô **Chép file** (tab Pin & Phần cứng): chạy `dd if=/dev/zero of=/tmp/dstest.bin bs=1m count=600`
     → số `↑` phải nhảy lên hàng trăm MB/s và tên ổ là `Macintosh HD` / `SSD nội bộ`;
     chép thẻ nhớ → ổ rời phải thấy tên volume của cả hai ổ trong tooltip.
  6. NAS: mount SMB rồi chép file; chip mạng hiện `LAN enX` với tốc độ tương đương
     lưu lượng thực (đối chiếu `netstat -ibn` trước/sau khi chép).

## 9. Điều khiển quạt (thêm lại, bản đơn giản kiểu iStat Menus)


### 9.1. Tính năng
- Thẻ **Quạt** trong tab "Nhiệt độ & Cảm biến": nút **System** (macOS tự điều khiển, mặc định), **Medium** (50% max RPM), **High** (80%), và **thanh trượt** tự chọn từ min RPM đến 100% (hiện `RPM (%)`). Ở chế độ System thanh trượt bám theo RPM thực tế.
- Không có rules editor, curve hay watchdog chống crash (quyết định của người dùng cho v1).

### 9.2. Cơ chế SMC (đã kiểm chứng trên M1, macOS 26)
- Ghi: `F0Md=01` (manual) rồi `F0Tg=<float32 little-endian>` (3000 RPM = `00803b45`). Không cần mở khoá `Ftst` (key trả "no data" trên M1); helper vẫn ghi `Ftst` nếu key tồn tại (M3/M4+ có thể cần, chưa kiểm thử).
- Trả về auto: `F0Md=00`, `F0Tg=00000000`.
- Đọc lại ngay sau khi ghi có thể ra giá trị cũ; `FanManager` chờ ~1.5s rồi kiểm chứng `F0Tg`, nếu lệch thì tự trả về System và báo lỗi.
- Đọc (không cần root): `Resources/smc -k F0Ac|F0Tg|F0Md|F0Mn|F0Mx|FNum -r` (định dạng `F0Ac  [flt ]  2985 (bytes ...)`, giá trị là trường thứ 4 khi tách theo khoảng trắng).

### 9.3. Helper đặc quyền
- `Resources/displaycontrol-power` cài vào `/Library/PrivilegedHelperTools/com.opensource.hypermac.power` (sudoers NOPASSWD chỉ cho user cài): `version` (in `HELPER_VERSION:4`), `fan-set <id 0-3> <rpm>`, `fan-auto <id>`, `sleep-disable on|off`.
- App yêu cầu `PrivilegedHelper.requiredVersion` (= 4); helper cũ → UI hiện nút cài lại (`BatteryManager.installHelper`, hỏi mật khẩu 1 lần). **Mỗi khi thêm lệnh vào helper phải tăng cả `HELPER_VERSION` lẫn `requiredVersion`.**
- **Cài helper từ thư mục dưới `~/Documents`** bằng `osascript ... with administrator privileges` sẽ lỗi `Operation not permitted` (root bị TCC chặn). Sao chép 3 file (`install-helper.sh`, `smc`, `displaycontrol-power`) ra `/private/tmp/...` rồi cài từ đó. App đã cài trong `/Applications` thì không gặp lỗi này.

### 9.4. An toàn
- Về System: khi thoát app (`applicationWillTerminate`), trước khi ngủ, khi khởi động app, khi chọn System.
- CPU peak / GPU / hotspot >= 90°C → ép về System; chỉ cho điều khiển lại khi < 80°C.
- Nếu app crash/force-quit khi đang Manual, quạt giữ tốc độ cuối cho tới khi mở lại HyperMac (tự reset về auto) hoặc khởi động lại máy.
- Không chạy cùng app điều khiển quạt khác (hai bên tranh `F0Tg`).

### 9.5. Kiểm thử
- Bấm High → `Resources/smc -k F0Tg -r` ≈ 5759, `F0Ac` tiến dần tới đó; Medium ≈ 3600; kéo thanh trượt 74% ≈ 5336; System → `F0Md` = 0, RPM giảm về 0.
- Thoát app khi đang Manual → quạt phải về auto.
- Đường 90°C chưa có hook giả nhiệt độ (chưa kiểm thử tự động).

### 9.6. Cập nhật tự động
- `UpdateManager.repo = "heintruong/HyperMac"`: kiểm tra GitHub Release mới nhất của fork, fallback `version.json` trên `main`. Khi phát hành bản mới phải bump đồng bộ `build.sh` (CFBundleVersion), `UpdateManager.currentVersion`, `version.json`.
- Updater không kiểm chữ ký bản tải về; tắt bằng `updatesDisabled = true` nếu không cần.

## 10. Tính năng riêng của fork

### 10.1. Gập máy vẫn chạy — `CaffeinateManager` + `LidAwakeCardView` (thẻ riêng dưới "Chống sleep màn")
- Công tắc gọi helper `sleep-disable on|off` → `pmset -a disablesleep 1|0` (máy không ngủ khi gập nắp, kể cả không cắm màn ngoài).
- Không lưu qua lần mở app. Khi thoát app → tắt đồng bộ. Nếu app crash khi đang bật, cờ `lid_awake_applied` khiến lần mở sau tự tắt.
- Helper chưa cài / cũ → công tắc báo lỗi + nút "Cài helper".
- Rủi ro: máy vẫn toả nhiệt khi gập — đừng bỏ balo khi đang bật.
- Màn hình vẫn tắt khi gập; chỉ chặn máy ngủ (độc lập với "Chống sleep màn" = giữ màn sáng).

### 10.2. Xếp chồng cửa sổ (cascade) — `WindowSnapManager.cascadeWindows(_:)`
- Lấy cửa sổ chuẩn (`AXStandardWindow`, layer 0, đang hiện) trên màn hình chứa cửa sổ trước nhất, theo thứ tự trước → sau (`CGWindowListCopyWindowInfo`), ghép với AX theo khung.
- `cascadeRects`: mọi cửa sổ ngang cùng kích thước `(1 - cascadeSpread)` = 90% vùng hiển thị; 10% còn lại chia đều cho các bước lệch nên cửa sổ sau luôn lộ một dải.
- `cascadeLayout`: cửa sổ dọc (cao > rộng × `portraitRatio` 1.15, vd. Android emulator) **giữ nguyên kích thước đang mở**, chỉ dời sát mép phải (căn trên, nhiều cái thì xếp cạnh nhau); cửa sổ ngang cascade ở phần còn lại. Chỉ toàn cửa sổ dọc → cascade thường.
  - `.topLeft` (⌃⌥[): cửa sổ trước nhất ở góc trên trái, các cửa sổ sau lệch dần xuống dưới phải.
  - `.bottomRight` (⌃⌥]): ngược lại.
- Kích hoạt: phím tắt (đổi được trong cài đặt phím tắt) hoặc 2 nút trong thẻ "Chia cửa sổ" của popover. Dùng `applyFrame` nên `⌃⌥⌫` (khôi phục kích thước) vẫn hoạt động sau khi xếp.
- Test: `Tests/ScreenshotAnnotationTests/CascadeTests.swift`.

### 10.4. Popover
- `NSPopover.animates = false` (mở tức thì). Không đặt nền đục cho `MainView` để popover dùng nền kính/vibrancy của macOS; thẻ dùng `Tone.card` (primary 5.5% opacity) thay cho `controlBackgroundColor`.

### 10.3. Vuốt 3 ngón để chuyển cửa sổ — `Sources/TrackpadSwipeSwitcher.swift`
- Công tắc trong thẻ "Chuyển cửa sổ" (key `alttab_gesture_enabled`, mặc định tắt). Tắt = không có event tap nào chạy.
- Event tap riêng, `.listenOnly`, chỉ nghe sự kiện gesture (type 29); đọc `NSEvent.allTouches()` → `SwipeTracker` (logic thuần).
- Vuốt ngang ≥ `openThreshold` → `WindowManager.handleShortcut` (phải = tới, trái = lùi); vuốt tiếp mỗi `stepThreshold` → `selectNext/Previous`; số ngón khác 3 → `handleModifierReleased()` (chuyển cửa sổ). Esc vẫn huỷ như bình thường.
- Cử chỉ 3 ngón của macOS ("Vuốt giữa các ứng dụng toàn màn hình") vẫn chạy song song → nên đổi sang 4 ngón trong Cài đặt Trackpad.
- Test: `Tests/ScreenshotAnnotationTests/SwipeTrackerTests.swift`.
