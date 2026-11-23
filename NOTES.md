# NOTES

- 2026-11-23：开发机为 macOS 27.0.1（26A434）、Xcode 27.2、Swift 6.4.2；系统默认 `xcrun` 找不到 SDK，构建脚本统一设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
- 2026-11-23：Homebrew ffmpeg 9.0.2 位于 `/opt/homebrew/bin`，带 libmp3lame；打包脚本递归复制 19 个 dylib，app 内置 ffmpeg 部分约 38 MB，整个 .app 约 40 MB。
- 2026-11-23：ffmpeg 9.0.2 用 `-attach cover.jpg` 生成 MKV 时，ffprobe 把图片报告为 `codec_type=video` 且 `disposition.attached_pic=1`，不是 `codec_type=attachment`；两条识别路径都要保留。
- 2026-11-23：`ffmpeg -progress pipe:1` 的 `out_time_ms` 实际单位是微秒（5 秒视频输出 5000000），进度解析同时兼容 `out_time_us` 与 `out_time_ms`。
- 2026-11-23：把 Homebrew ffmpeg 放入 app 后必须用 `install_name_tool` 把绝对 dylib 依赖改写为 `@executable_path/../lib` / `@loader_path`，并在清空环境变量的情况下运行验证通过。
- 2026-11-23：系统 Python 无 Pillow；图标生成请使用带 Pillow 的 Python 环境。
- 2026-11-23：CLI 与集成测试已验证 MP4 内嵌封面、MKV attached picture、MOV 第 1 秒截帧、0.6 秒短视频回退第 0 秒、同名自动重命名、无封面输出。
- 2026-11-23：SwiftUI 应用接收 Finder「打开方式」文件时，`WindowGroup` + `CFBundleDocumentTypes` 会为每个文件/每次打开创建额外窗口；改用单例 `Window("音萃 SoundDistill", id: "main")` 后保持单窗口，`open -a` 批量打开文件在冷启动和运行中均验证通过。
- 2026-11-23：最终 app 内置 ffmpeg 转换 2 分钟测试视频输出 MP3 的音频流码率实测 320000 bps、带 1280×720 mjpeg 封面；`build/音萃 SoundDistill-1.0.0.dmg` 18 MB。
- 2026-11-23：审查修复后，转换先写同目录隐藏临时 MP3，校验成功后原子替换最终文件；overwrite 失败/取消不再删除原有文件。同名并发由 OutputPathReservoir 预留路径，CLI 连续 10 次并发测试均生成 2 个文件。
- 2026-11-23：当前 Homebrew ffmpeg 的 minOS 为 27.0，`build_app.sh` 会读取该值并同步 `LSMinimumSystemVersion`；当前 DMG 实际要求 macOS 27+，源码仍支持 macOS 14（使用匹配的 ffmpeg 自行构建）。
- 2026-11-23：业务优化后，低采样率按 MP3 合法码率自动适配：22.05 kHz → 160 kbps、8 kHz → 64 kbps，并在结果 warnings/UI/CLI 中显示；26 个测试全部通过。
- 2026-11-23：新增按任务选择音轨（默认跟随容器 disposition.default）、队列持久化（Application Support/SoundDistill/queue.json）、批次完成汇总面板、保持原目录结构开关；已验证队列重启恢复和批次汇总 UI。
- 2026-11-23：界面统一使用 `.focusEffectDisabled()` 关闭 macOS 默认蓝色键盘对焦框；同名文件策略从系统 Picker 改为主题化 Menu，避免系统蓝色控件破坏深色品牌界面。
