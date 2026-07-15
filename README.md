# 便签 StickyNotes 📝

一个轻量、好看的 macOS 桌面便签应用。原生 Swift + SwiftUI 编写，无任何第三方依赖，编译产物只有几百 KB。

A lightweight, beautiful sticky notes app for macOS. Built with native Swift + SwiftUI, zero dependencies.

## 截图

<table>
  <tr>
    <td align="center"><b>📝 文字便签</b><br><sub>Markdown 渲染 · 玻璃拟态</sub></td>
    <td align="center"><b>✅ 待办事项</b><br><sub>打勾自动划掉</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/note-text.png" width="330" alt="文字便签: Markdown 预览效果"></td>
    <td><img src="docs/screenshots/note-todo.png" width="310" alt="待办事项便签"></td>
  </tr>
</table>

<b>🕰 历史便签</b> —— 删除的便签按日期归档, 随时回顾每天做了什么, 可一键恢复<br>
<img src="docs/screenshots/history.png" width="480" alt="历史便签: 按日期分组回顾">

<br><b>📏 折叠便签 + 屏幕边缘吸附</b> —— 一键折叠成一行标题条 (待办自动带完成进度);
拖到屏幕左/右边缘自动吸附, 贴边端被"切平", 松手平滑归位并伴随触控板触感反馈<br>
<img src="docs/screenshots/capsule-todo-snapped.png" width="190" alt="吸附左边缘的待办折叠条, 带 2/4 进度, 左端切平"><br>
<img src="docs/screenshots/capsule-text-snapped.png" width="112" alt="吸附左边缘的文字便签折叠条"><br>
<img src="docs/screenshots/capsule-free.png" width="135" alt="未吸附的折叠条, 两端圆角胶囊形">

## 功能

- **两种便签类型**
  - 📝 **文字便签**：支持 Markdown（标题、列表、待办语法、引用、粗体/斜体/行内代码、分割线），一键切换编辑/预览
  - ✅ **待办事项**：逐条添加待办，点勾选框完成后自动划掉，支持编辑、删除单条
- **三种窗口模式**（每张便签独立设置）
  - 📌 置顶悬浮 —— 永远盖在其他窗口上
  - 🪟 普通窗口 —— 和普通应用一样
  - 🖥 贴在桌面 —— 沉到桌面层，像小组件一样贴着壁纸，不遮挡任何操作
- **历史便签**：删除的便签自动按日期归档，按天分组回顾过去做了什么，可一键恢复
- **折叠便签**：一键收起成一行标题条，标题取自第一行内容且永不省略，待办便签带完成进度（如 `2/4`），折叠状态重启后保持
- **边缘吸附**：折叠条拖近屏幕左/右边缘自动吸平，贴边端圆角变直角（被屏幕"切割"的效果），带触控板触感反馈，松手平滑归位
- **预览里直接打勾**：文字便签预览模式下，`- [ ]` 渲染出的方框可直接点击勾选/取消，原文自动同步
- **AI 集成（MCP）**：内置 MCP 服务器，Codex / Claude 等 AI 助手可直接创建、修改、查阅便签（见下文）
- **五种柔和配色**：莫兰迪色系的柠檬黄 / 蜜桃粉 / 薄荷绿 / 天空蓝 / 丁香紫
- **玻璃拟态设计**：磨砂半透明背景、渐变玻璃边框、衬线体标题
- **自动保存**：停止输入 1 秒后自动写盘，位置、大小、颜色、模式全部记住
- **开机自启**：菜单栏一键开关
- **不打扰**：不占 Dock，安静地住在菜单栏；无边框圆角卡片设计

## 安装

需要 macOS 14+ 和 Xcode Command Line Tools（`xcode-select --install`）。

```bash
git clone git@github.com:simony3/StickyNotes.git
cd StickyNotes
./build.sh
open /Applications/StickyNotes.app
```

`build.sh` 会编译、打包成 `.app`、签名（ad-hoc）并安装到 `/Applications`。

## 使用

| 操作 | 方法 |
|---|---|
| 新建便签 | 菜单栏 📝 图标，或便签顶栏 **+**（都会让你选类型） |
| 移动 | 按住便签任意位置拖动 |
| 调整大小 | 拖拽便签边缘 |
| 换颜色 / 切换窗口模式 | 鼠标悬停在便签顶栏 |
| 编辑 / 预览 | 顶栏 ✏️ / 👁 按钮 |
| 折叠 / 展开 | 顶栏最右侧折叠按钮 |
| 贴边吸附 | 拖动折叠条靠近屏幕左/右边缘（16pt 内自动吸附，拖离恢复） |
| 待办打勾 | 待办便签点方框；文字便签预览模式下点 `- [ ]` 方框同样有效 |
| 删除便签 | 顶栏左上角 ✕（会归档进历史，可找回） |
| 查看/恢复历史便签 | 菜单栏 →"历史便签" |
| 召唤所有便签 | 点 app 图标 |

### Markdown 速查（文字便签）

```markdown
# 大标题   ## 中标题   ### 小标题
- 无序列表
- [ ] 待办   - [x] 已完成
> 引用
**粗体** *斜体* `代码`
---
```

## AI 集成（MCP）

项目内置一个零依赖的 [MCP](https://modelcontextprotocol.io/) 服务器（`mcp/stickynotes_mcp.py`，系统自带 Python 即可运行），把便签能力暴露给任何支持 MCP 的 AI 客户端（Codex、Claude Desktop、Claude Code 等）。配置好之后，直接对 AI 说"帮我把明天的学习计划贴成便签"，便签就会出现在屏幕上。

**提供的工具：**

| 工具 | 说明 |
|---|---|
| `create_note` | 创建便签（类型 / 颜色 / 窗口模式 / 折叠等全参数） |
| `update_note` | 修改已有便签的内容或颜色（按 id） |
| `list_notes` | 读取当前所有便签 |
| `list_history` | 读取历史归档 |
| `overwrite_data` | 万能工具：整体重写便签数据（自动备份 + 重启 app），删除、改模式、恢复历史等一切操作都由它兜底 |

**配置方法（Codex 桌面版）**——在 `~/.codex/config.toml` 中追加：

```toml
[mcp_servers.stickynotes]
command = "python3"
args = ["/你的路径/StickyNotes/mcp/stickynotes_mcp.py"]
```

**配置方法（Claude Code）**：

```bash
claude mcp add stickynotes -- python3 /你的路径/StickyNotes/mcp/stickynotes_mcp.py
```

重启客户端后 AI 即可看到上述工具。

## 数据存储

便签内容保存在 `~/Library/Application Support/StickyNotes/notes.json`，纯 JSON 明文，方便备份和迁移。

## 项目结构

```
Sources/StickyNotes/
├── main.swift          # 入口, NSApplication 启动, 隐藏编辑菜单(快捷键支持)
├── AppDelegate.swift   # 菜单栏、便签窗口管理、类型选择、URL 接口
├── Note.swift          # 数据模型 + JSON 持久化 + 待办条目读写 + 历史归档
├── NoteView.swift      # SwiftUI 界面: 便签视图、待办清单、Markdown 渲染、折叠条
├── HistoryView.swift   # 历史便签窗口: 按日期分组、恢复、彻底删除
└── NoteWindow.swift    # 无边框窗口、三种层级模式、折叠与边缘吸附
mcp/
└── stickynotes_mcp.py  # MCP 服务器: AI 客户端控制便签的入口
```

## License

[MIT](LICENSE)
