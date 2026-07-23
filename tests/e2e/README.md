# E2E（XCUITest）—— Step 9 已落地

工作流第 9 步 E2E。因 **SwiftPM 无法承载 XCUITest UI 测试 target**，用 [xcodegen](https://github.com/yonaskolb/XcodeGen) 从
[`project.yml`](../../project.yml) 生成含 App host + UITest target 的工程；测试 **只驱动宠物窗（NSPanel）**——
菜单栏 `NSStatusItem` 不在 app 窗口树内、XCUITest 无法寻址，故不纳入。

## 跑法

```bash
brew install xcodegen                        # 一次性
xcodegen generate                            # 生成 agentmon.xcodeproj（已 gitignore）
xcodebuild test \
  -project agentmon.xcodeproj \
  -scheme agentmonApp \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

> ⚠️ XCUITest 需要 **GUI 会话**：无头 shell 会在 bootstrap 阶段被 kill（`signal kill before establishing connection`）。
> 因此本地只能做到「编译级」验证（`xcodebuild build-for-testing`），真正运行在 **CI（`macos-14`，有 GUI）** 完成——
> 见 [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) 的 `uitest` job。

## 测试可控性（已实现）
- `AGENTMON_HOME`：重定向 spool/state/config 到临时目录（`AgentmonPaths`）。
- `AGENTMON_CLAUDE_SETTINGS`：重定向 Claude settings 路径。
- `AGENTMON_UITEST`：App 以 `.regular` 激活策略运行，便于 XCUITest 寻址窗口。
- `CatView` 暴露无障碍：`identifier="pet.state"`、`value="<mood>:<level>"`（如 `working:1`），断言不依赖中文文案。

## 已实现用例（[`UITests/PetPanelUITests.swift`](../../UITests/PetPanelUITests.swift)）
- **testPetShowsWorking**：启动前投递 `UserPromptSubmit` → 宠物窗 `pet.state` 值以 `working:` 开头。
- **testPetReturnsToIdleAfterCompletion**：再投 `Stop` → 下一 tick 后值回落 `idle:`。

## 后续可补场景（尚未落地）
- 进化换肤：注入近门槛能量 + 完成事件 → 断言值出现 `evolve:`/level 递增。
- 启用/停用 Claude 集成：用 `AGENTMON_CLAUDE_SETTINGS` 指向临时文件断言注入/回滚（当前由集成测试
  `ClaudeHookInstallerTests` 覆盖同等逻辑）。
