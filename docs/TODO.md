# DesktopPet 待办 / 后续工作

> 与 `docs/requirements.md` 目标对照后的缺口清单；完成项请勾掉并可在 PR 中注明。

## 高优先级

- [ ] **真实动画管线**：用序列帧或 GIF（先打通一种状态即可）替换 `PetAnimationDriver` 占位大字；与 `PetStateMachine` 状态绑定播放/循环。
- [ ] **资源目录**：按 PRD 建立 `Resources/Animations/`（idle、walk、keytap、jump、sleep 等）与加载路径；缺失时降级提示。
- [ ] **单元测试**：新增 Test 目标；至少覆盖 `PetStateMachine` 迁移、巡逻边界/可见区、`PetConfig.exteriorHitSide` 与缩放锚点相关逻辑（可选）。

## 中优先级

- [ ] **鼠标互动打磨**：按距离、速度、停留时间细化触发阈值；验收「接近/远离自然、无高频抖动」（PRD F3）。
- [ ] **巡逻与 walk**：巡逻节奏与 `walk` 状态/动画语义对齐；巡逻间隔可进设置（当前多为常量）。
- [ ] **无辅助功能降级**：明确无权限时的行为（仅本地键、仅菜单提示等）并写进 README/PRD。
- [ ] **多屏 / Space / 全屏回归**：验证 `collectionBehavior`、外接显示器、深色模式；必要时增加「按配置」的 Space 行为开关（PRD F1）。
- [ ] **菜单栏热点避让**：巡逻/落点不长期压在菜单栏关键交互区（PRD F6 验收）。

## 低优先级 / 产品扩展

- [ ] **动画模式切换**：设置中切换「序列帧 / 视频」等（PRD 配置项）；对应 `AnimationDriver` 多后端。
- [ ] **快捷键自定义**：除默认 ⌘K 外支持用户改键并持久化。
- [ ] **性能与可观测性**：空闲 CPU、监听与动画解耦的采样或简单日志基准（PRD 6.3）。
- [ ] **权限流测试**：UI 或集成测试覆盖 onboarding + 重检（可选）。

## 工程与发布

- [ ] **README 许可证**：由「待补充」改为 MIT 或实际许可证全文。
- [ ] **验收清单**：在 `docs/requirements.md` 第 9 节将已实现项改为 `[x]`，并保留为发版前检查表。
- [ ] **PRD 结构树对齐**：文档中 `KeyboardMonitor` / `GIFPlayer` 等与当前仓库文件名不一致处，择期与源码同步或标注「规划中」。
- [ ] **分发**（若对公众发布）：Developer ID 签名、公证、分发说明；若考虑 Mac App Store，需单独评估沙盒与权限方案。

## 已完成（便于对照，可随进度删减）

- [x] 菜单栏 accessory、`NSPanel` 桌宠窗口、穿透与命中包络、`petScale` 与窗口锚定缩放。
- [x] 辅助功能引导、Bundle ID、`NSAccessibilityUsageDescription`、TCC 诊断与延迟重检、全局键与 ⌘K。
- [x] 状态机骨架、巡逻调度、设置持久化（穿透/巡逻/缩放）、`visualBaselineFactor` 默认体量。
