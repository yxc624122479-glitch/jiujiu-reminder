# 玖玖提醒

轻量 Mac 本地桌宠提醒应用。使用 Swift + AppKit 构建，不接入网络，配置保存在本机 `UserDefaults`。

玖玖会常驻桌面，用不同动作提示工作、休息、喝水和状态切换。桌宠素材来自 `Resources/spritesheet.png`，按 Codex Pet 的 `8 x 9` atlas 约定组织。

App 图标来自玖玖猫咪形象，打包脚本会自动把 `Resources/AppIcon.icns` 写入 `.app`。

## 功能

- 桌面透明悬浮宠物窗口，可拖拽并保存位置。
- 工作 / 休息循环提醒。
- 喝水间隔提醒，支持稍后提醒。
- 右键菜单支持暂停、继续、重置本轮、设置时间、切换动作展示。
- 可选开机启动入口。

## 环境要求

- macOS 13 或更新版本
- Swift 6 工具链

## 开发运行

```bash
swift run
```

首次启动会要求设置工作时长、休息时长和喝水间隔。桌宠可拖拽，右键打开菜单。

## 打包

```bash
chmod +x scripts/build_app.sh
./scripts/build_app.sh
open "dist/Jiujiu Reminder.app"
```

生成的 `.app` 位于 `dist/Jiujiu Reminder.app`，可以移动到 `/Applications`。

## 项目结构

```text
.
├── Package.swift
├── Resources/
│   ├── AppIcon.icns
│   ├── AppIcon.png
│   └── spritesheet.png
├── Sources/JiujiuReminderApp/
│   ├── AppDelegate.swift
│   ├── PetWindowController.swift
│   ├── ReminderEngine.swift
│   ├── SettingsWindowController.swift
│   └── SpriteSheet.swift
└── scripts/
    └── build_app.sh
```

## 验证建议

- 把工作、休息、喝水都临时设为 1 分钟，确认提醒流程。
- 右键桌宠确认暂停、继续、重置本轮、设置时间可用。
- 拖动桌宠后退出重开，确认位置被保存。

## License

MIT
