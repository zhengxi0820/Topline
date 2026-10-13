# Topline — 酷狗歌词全屏悬浮窗（macOS）

> Topline：音乐术语"主旋律声部"，也是"顶部那行歌词"。

菜单栏常驻的小工具：在屏幕顶部显示一条半透明歌词条，**全屏应用之上也能显示**，跟着酷狗音乐（以及任何上报系统"正在播放"的播放器）逐字 KTV 滚动。

## 功能

- **逐字 KTV 填充**：当前行按演唱进度从左向右点亮（酷狗官方逐字时间轴），下一行预告
- **版本精确匹配**：优先读酷狗客户端自己的歌词缓存（本地 KRC，与正在播放的音频精确对应，翻唱/Live 不串词）
- **双网源回退**：本地没有时自动走 酷狗歌词接口 → 网易云，命中后写磁盘缓存，每版一生只请求一次
- **手动保底**：菜单「歌词版本…」列出全部候选（本地各版本 + 酷狗 + 网易云）双击切换并记住绑定；「恢复自动匹配」一键还原
- **时间微调**：歌词提前/延后 0.2s 步进（每曲独立记忆，默认 0）
- **样式 DIY**：8 个旋钮（字体/字号/三色/两级透明度/条宽），默认苹方，实时预览，一键恢复默认
- 全屏应用、全屏 Space 之上正常置顶；歌词条可拖动（原生拖动，跟手）、可锁定（点击穿透）、可隐藏

## 原理

```
系统"正在播放"(MediaRemote) ←── 酷狗/网易云/… 上报
        │  macOS 15.4+ 该私有接口有权限校验，第三方进程直读为空
        ▼
/usr/bin/perl 宿主加载 MediaRemoteAdapter.framework（苹果签名的系统二进制不受限）
        │  输出 JSON（歌名/歌手/时长/进度/倍速），1s 轮询 + 进度插值
        ▼
歌词来源（按优先级）：
  1. 酷狗本地 KRC 缓存（krc1 = XOR 16字节密钥 + 标准 zlib，含逐字时间轴与版本时长）
  2. 酷狗歌词接口（lyrics.kugou.com，LRC）
  3. 网易云接口（music.163.com，LRC）—— 多版本按时长就近+歌手匹配挑选
        ▼
Topline 悬浮窗（NSPanel 置顶 + fullScreenAuxiliary，双层 CATextLayer KTV 填充）
```

播放信息适配来自开源项目 [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)（BSD 3-Clause，见 THIRD_PARTY_LICENSES.md）v0.7.7，源码编译，去掉了依赖测试客户端的 `test` 目标。zlib 解压直接链接系统 libz。

## 构建与安装

```bash
./build.sh            # 编译并打包 build/Topline.app
./build.sh --install  # 安装到 /Applications 并启动（覆盖旧版本）
```

开发调试（不安装，前台跑、带日志）：

```bash
swift build -c release
TOPLINE_DEBUG=1 .build/release/Topline
```

## 使用

- 菜单栏"词"图标：隐藏/显示、锁定位置、歌词微调、歌词版本…、样式…、退出
- 歌词条直接拖动换位置（原生拖动），松手自动记住
- 歌词缓存：`~/Library/Application Support/Topline/lyrics/`，删掉即重搜

## 已知边界与维护风险

- 酷狗本地缓存目录（`~/Library/Containers/com.kugou.mac.Music/.../kgLyric/`）是私有实现，酷狗客户端大改版后需要跟进；纯数字命名的缓存文件不参与匹配
- 酷狗/网易云均为非官方接口：可能随时间收紧或变更（2026-10 实测酷狗搜索接口对本机返回空，网易云稳定兜底）
- MediaRemote 是私有框架：macOS 大版本升级后 perl 宿主方案可能需要跟随 mediaremote-adapter 项目更新（重编译 framework 替换 `Resources/lib/` 即可）
- KRC 加密为公开逆向算法，历史上十余年未变
- 仅限个人使用与小范围朋友间分享，请勿公开分发（歌词数据版权属于平台方）

## 测试

```bash
swift test   # 50 个单测：KRC 解密往返（python 地面真值夹具）、LRC 解析、
             # 逐字填充数学、选版打分、绑定/偏移持久化、真实抓包 JSON 解码
```
