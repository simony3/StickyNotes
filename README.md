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

## 功能

- **两种便签类型**
  - 📝 **文字便签**：支持 Markdown（标题、列表、待办语法、引用、粗体/斜体/行内代码、分割线），一键切换编辑/预览
  - ✅ **待办事项**：逐条添加待办，点勾选框完成后自动划掉，支持编辑、删除单条
- **三种窗口模式**（每张便签独立设置）
  - 📌 置顶悬浮 —— 永远盖在其他窗口上
  - 🪟 普通窗口 —— 和普通应用一样
  - 🖥 贴在桌面 —— 沉到桌面层，像小组件一样贴着壁纸，不遮挡任何操作
- **历史便签**：删除的便签自动按日期归档，按天分组回顾过去做了什么，可一键恢复
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

## 数据存储

便签内容保存在 `~/Library/Application Support/StickyNotes/notes.json`，纯 JSON 明文，方便备份和迁移。

## 项目结构

```
Sources/StickyNotes/
├── main.swift          # 入口, NSApplication 启动
├── AppDelegate.swift   # 菜单栏、便签窗口管理、类型选择
├── Note.swift          # 数据模型 + JSON 持久化 + 待办条目读写 + 历史归档
├── NoteView.swift      # SwiftUI 界面: 便签视图、待办清单、Markdown 渲染
├── HistoryView.swift   # 历史便签窗口: 按日期分组、恢复、彻底删除
└── NoteWindow.swift    # 无边框窗口、三种层级模式
```

## License

[MIT](LICENSE)
