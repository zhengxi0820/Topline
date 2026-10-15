# Topline 项目规则（AI 协作）

全局规则见 `~/.zcode/AGENTS.md`，本文件只记录本项目的例外与补充。

## 命令速查

- 构建安装：`./build.sh --install`（打包 /Applications/Topline.app 并重启）
- 本地调试：`swift build -c release && TOPLINE_DEBUG=1 .build/release/Topline`（stderr 实时日志）
- 回归测试：`swift test`——**测试框架指定 swift-testing**（命令行工具没有 XCTest 模块，勿改回）；改完必须全绿再交付

## 对全局规则的例外

- 第 19 条（前端原型先行）：本项目关闭——原生 macOS 工具非 Web 前端；UI/交互改动直接实机验证（可 `screencapture` 截图自证）

## 红线与踩坑（动这些之前先看清注释）

- **苹果的 zlib 是假的**：`NSData.decompressed` / Compression 框架的 `.zlib` 均为私有变体，解不了酷狗 KRC 的标准 zlib 流；解压只能走系统 libz（`Sources/CZlibShim`）
- **KRC 密钥以 `KRC.swift` 里的 16 字节为准**；网上流传的经典 19 字节密钥串是错的，勿凭记忆改写
- `Resources/bin`（perl 脚本）与 `Resources/lib`（MediaRemoteAdapter.framework）是读"正在播放"的唯一通道，勿删勿改；项目不依赖 Xcode
- 目录改名/移动后必须先 `rm -rf .build`（绝对路径缓存失效，报 PCH 错误就是它）
- 推送：SSH 专用钥 `id_ed25519_github` 走 `ssh.github.com:443`（`~/.ssh/config` 已配），直接 `git push` 即可，无需代理
- 歌词条 UI 的视觉行为必须截图验收，日志只能证明逻辑不能证明渲染（KTV 遮罩 bug 的教训）

## 文档指针

- `README.md`：原理链路、构建使用、维护风险（面向外部读者，改架构时同步更新）
