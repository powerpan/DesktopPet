# DesktopPet

基于 SwiftUI 的 macOS 桌面应用脚手架：默认窗口展示简单界面，可作为「桌宠」类应用的起点。

## 环境要求

- macOS **14.0** 或更高
- **Xcode**（建议当前稳定版，含 Swift 5）
- SwiftUI

## 运行方式

1. 克隆仓库：

   ```bash
   git clone https://github.com/powerpan/DesktopPet.git
   cd DesktopPet
   ```

2. 用 Xcode 打开工程根目录下的 `DesktopPet.xcodeproj`。

3. 选择目标为 **My Mac**，按 **Run**（⌘R）编译并运行。

默认窗口尺寸约为 480×360，可在 `DesktopPetApp.swift` 中调整 `defaultSize`。

## 工程结构

| 路径 | 说明 |
|------|------|
| `DesktopPet/DesktopPetApp.swift` | 应用入口与 `WindowGroup` 配置 |
| `DesktopPet/ContentView.swift` | 主界面（示例动画与文案） |
| `DesktopPet/Assets.xcassets/` | 颜色与图标资源 |
| `DesktopPet.xcodeproj/` | Xcode 工程与共享 Scheme |

## 许可证

若需开源，请在此补充许可证说明（例如 MIT）。
