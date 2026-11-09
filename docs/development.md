# 开发说明

这是可独立构建的 Mac 项目，不需要检出 Chrome 仓库。保留 `apps/macos/` 路径以便追溯来源，共用 UI 已随仓库提供。

## 准备和检查

环境及安装步骤见 [README](../README.md)。安装 npm 依赖后，常用命令为：

```sh
npm run typecheck
npm run lint
npm run test:web
npm run test:native
npm run test:e2e
npm run build
npm run package
```

界面测试和图标构建需要 `npx playwright install chromium`。原生测试使用 Swift Testing，包装脚本包含当前 Command Line Tools 的框架路径；工具链布局不同的机器可能需要按实际路径调整。

测试默认使用模拟接口，无需真实 Key，不自动产生模型费用。浏览器中的界面模拟不能代替真实辅助功能、截图、全局快捷键或系统授权测试。

## 目录

| 目录 | 职责 |
| --- | --- |
| `apps/macos/web/` | React 页面、状态及原生桥接客户端 |
| `src/ui/` | 消息、输入、Markdown、菜单等展示组件 |
| `apps/macos/native/Sources/ReadingCore/` | 会话、草稿、上下文和请求状态 |
| `apps/macos/native/Sources/ReadingStorage/` | SQLite 和图片文件保存 |
| `apps/macos/native/Sources/MacServices/` | 划词、截图、钥匙串、权限和快捷键 |
| `apps/macos/native/Sources/DeepSeekTransport/` | 官方 API 请求和流式解析 |
| `apps/macos/native/Sources/AnySidebarMac/` | 窗口、小助手、菜单及应用组装 |
| `apps/macos/contracts/` | 桥接命令、模型能力、提示和公开测试夹具 |
| `tests/macos/` | Web 单元及布局测试 |
| `scripts/macos/` | 构建、签名、测试、审计及安装 |

React 运行在 WKWebView 中。原生端管理数据、Key 和请求，页面只通过受校验的命令调用能力，不读取已保存 Key，也没有任意文件访问接口。应用没有 Electron 或本地 HTTP 服务。

## 构建与安装

`npm run build` 依次生成 Web 资源和图标、编译 arm64 原生程序并签名。`npm run package` 审计当前构建后生成 ZIP，不代替构建，也不自动安装或上传。

```sh
npm run install:local
open ~/Applications/AnySidebarMac.app
```

更新前正常退出旧版。安装脚本验证暂存包后原子替换应用目录，保留应用外的数据与钥匙串项。不要把两个版本的 Contents 文件夹合并。

本机签名见 [README](../README.md#本机签名与更新)。专用私钥保存在用户钥匙串，指纹配置位于 `~/Library/Application Support/com.decous.anysidebar.mac-build/signing.json`；配置不可用时不静默退回临时签名。面向他人分发还需要 Developer ID、Apple 公证和相应实机验证。

## 数据和请求约定

- 打开面板、划词、截图不调用模型。发送时冻结问题、资料与历史。
- 重试和重新生成沿用冻结的资料，采用当前模型设置，不自动重试收费调用。
- 超出文本、图片或请求体预算时明确报错，不静默删图或截断历史。
- Key 不进入会话、快照、日志和报告；已保存的 Key 不回传 Web 页面。
- 网页、文档、图片和旧回答均为参考资料，不能以其中的指令改变助手职责。

应用数据目录为 `~/Library/Application Support/com.decous.anysidebar.mac/`，Key 在系统钥匙串。仓库、应用包和个人数据分开，构建不会读取个人对话作为资源。

## 验证边界

已在开发机器验证文字提问及追问、基本采集和权限流程。图像理解质量、macOS 14 实机、双屏和完整性能矩阵仍待验证。[公开评测样例](macos/reading-evaluation.md)用于组织检查，模拟输出不能证明语义质量改善。

现有 `*:mac` 脚本保留为兼容入口，常用命令可使用上方的简短名称。
