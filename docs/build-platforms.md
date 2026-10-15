# 各平台构建指南

环境要求：安装 [Flutter SDK](https://docs.flutter.dev/get-started/install)（stable 渠道，3.27+），并 `flutter doctor` 确认对应平台的工具链就绪。

```bash
git clone <本仓库地址>
cd team-chat/app
flutter pub get
```

## Windows

需要 Visual Studio 2022（勾选「使用 C++ 的桌面开发」工作负载）。

```bash
flutter build windows --release
# 产物：build/windows/x64/runner/Release/ 整个目录（含 team_chat.exe），压缩后即可分发
```

## macOS

需要 Xcode（App Store 安装后执行 `sudo xcode-select --switch /Applications/Xcode.app`）。

```bash
flutter build macos --release
# 产物：build/macos/Build/Products/Release/team_chat.app
```

未签名应用首次打开：右键 → 打开；或 `xattr -cr team_chat.app` 后再运行。

## Linux

```bash
sudo apt-get install -y ninja-build libgtk-3-dev clang cmake pkg-config liblzma-dev
flutter build linux --release
# 产物：build/linux/x64/release/bundle/（可执行文件 team_chat + 依赖库）
```

## Android

需要 JDK 17 与 Android SDK（Android Studio 安装后 `flutter doctor --android-licenses` 接受协议）。

首次构建若提示 `NDK 28.2.13676358` 缺失，用安装器补装即可（约 1GB，仅首次）：

```bash
sdkmanager --install "ndk;28.2.13676358"    # 或新版命令行工具：sdkmanager --install "ndk/28.2.13676358"
# 也可以在 Android Studio 的 SDK Manager → SDK Tools 勾选 NDK (Side by side) 安装
```

```bash
flutter build apk --release          # 通用 APK
flutter build apk --split-per-abi    # 按架构拆分，体积更小
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

默认使用 debug 签名，可直接安装测试。正式分发请配置自己的签名：

```bash
keytool -genkey -v -keystore teamchat.jks -keyalg RSA -keysize 2048 -validity 10000 -alias teamchat
```

在 `app/android/key.properties` 中配置（该文件已被 .gitignore 排除）：

```properties
storePassword=<密码>
keyPassword=<密码>
keyAlias=teamchat
storeFile=<teamchat.jks 的绝对路径>
```

并按 [Flutter 官方文档](https://docs.flutter.dev/deployment/android#signing-the-app) 在 `android/app/build.gradle.kts` 中引用。

## iOS

iOS 无法产出「开箱即用」的公共安装包：必须使用 Apple 开发者账号签名。

1. 在 macOS 上打开 `app/ios/Runner.xcworkspace`（或直接 `flutter build ios --release`）
2. Xcode → Signing & Capabilities → 选择你的 Team 与 Bundle Identifier
3. 分发方式：
   - 自用少量设备：`flutter build ipa` 导出 ad-hoc / development 包
   - TestFlight / App Store：Xcode → Product → Archive → Distribute App

> 没有付费开发者账号时，可用免费 Apple ID 在 Xcode 里直连设备调试安装（7 天有效期）。

## 鸿蒙 HarmonyOS (OpenHarmony / HarmonyOS NEXT)

鸿蒙端使用 OpenHarmony 社区的 Flutter 分支构建，步骤：

1. 环境准备：
   - 安装 **DevEco Studio 5.x** 与 **HarmonyOS SDK**（API 12+）
   - 安装 `ohpm`、`hvigor`（DevEco 自带，配好环境变量）
2. 获取 OpenHarmony-SIG 的 Flutter 分支：
   ```bash
   git clone https://gitee.com/openharmony-sig/flutter_flutter.git
   cd flutter_flutter && git checkout <与新版接近的稳定分支，如 3.27.x-ohos>
   # 按仓库 README 配置：export PATH=<flutter_flutter>/bin:$PATH
   ```
3. 为本项目生成 ohos 平台目录并构建：
   ```bash
   cd team-chat/app
   flutter create --platforms ohos .     # 使用 OHOS 版 flutter 执行，生成 ohos/ 工程
   flutter pub get
   flutter build hap --release
   # 产物：app/ohos/entry/build/default/outputs/default/entry-default-signed.hap
   ```
4. 用 DevEco Studio 打开 `app/ohos/` 完成签名（需要华为开发者账号配置证书），即可分发安装。

> 注意：请使用 OHOS 分支的 flutter 命令操作本项目（Dart 依赖会自动解析到与该分支兼容的版本区间）。

## 自动发布（GitHub Actions）

本仓库内置两条工作流：

- `.github/workflows/ci.yml`：每次 push / PR 自动跑 `flutter analyze` + `flutter test`
- `.github/workflows/release.yml`：推送 `v*` 标签自动构建 **Windows / Linux / macOS / Android** 产物并发布到 GitHub Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

iOS 与鸿蒙因需要商业签名/私有 SDK，未纳入 CI，按上文本地构建。
