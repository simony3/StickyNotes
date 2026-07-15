#!/usr/bin/env python3
"""StickyNotes MCP 服务器 (stdio, 零依赖)

把便签 app 的能力暴露成 MCP 工具, 供 Codex / Claude 等 AI 客户端调用:
  - create_note   创建便签 (底层调 stickynotes:// URL Scheme)
  - list_notes    查看当前所有便签
  - list_history  查看历史归档便签
"""
import datetime
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.parse
import uuid

DATA_DIR = os.path.expanduser("~/Library/Application Support/StickyNotes")
APP_PATH = "/Applications/StickyNotes.app"

TOOLS = [
    {
        "name": "create_note",
        "description": (
            "在用户的 macOS 桌面上创建一张便签。text 为便签内容; "
            "待办便签 (kind=todo) 每行一条任务, 用 '[ ] ' 开头表示未完成, '[x] ' 表示已完成; "
            "文字便签 (kind=text) 支持 Markdown (# 标题 / - 列表 / > 引用等)。"
            "创建多张便签就多次调用本工具。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "便签内容"},
                "kind": {
                    "type": "string",
                    "enum": ["text", "todo"],
                    "description": "便签类型: text=文字便签(支持Markdown), todo=待办清单",
                },
                "theme": {
                    "type": "string",
                    "enum": ["lemon", "peach", "mint", "sky", "lilac"],
                    "description": "颜色主题, 不传则自动轮换取色",
                },
                "mode": {
                    "type": "string",
                    "enum": ["floating", "normal", "desktop"],
                    "description": "窗口模式: floating=置顶悬浮(默认), normal=普通窗口, desktop=贴在桌面",
                },
                "preview": {
                    "type": "boolean",
                    "description": "true 则以 Markdown 预览模式打开 (仅对 text 类型有意义)",
                },
                "collapsed": {
                    "type": "boolean",
                    "description": "true 则折叠成一行标题条",
                },
            },
            "required": ["text", "kind"],
        },
    },
    {
        "name": "update_note",
        "description": (
            "修改一张已存在便签的内容。先用 list_notes 拿到便签的 id, "
            "再传入新的完整内容 (text 会整体替换原内容, 不是追加)。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "便签 id (从 list_notes 获取)"},
                "text": {"type": "string", "description": "新的完整内容, 整体替换"},
                "theme": {
                    "type": "string",
                    "enum": ["lemon", "peach", "mint", "sky", "lilac"],
                    "description": "可选, 同时换颜色",
                },
            },
            "required": ["id", "text"],
        },
    },
    {
        "name": "list_notes",
        "description": "列出用户当前屏幕上的所有便签, 含 id (供 update_note 使用)、内容、类型、颜色、折叠状态。",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "list_history",
        "description": "列出已删除归档的历史便签 (按删除时间倒序)。",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "overwrite_data",
        "description": (
            "万能工具: 直接整体重写便签数据, 可实现其他工具做不到的一切操作 — "
            "删除便签、改窗口模式/折叠状态/位置、恢复或清理历史归档等。"
            "用法: 先 list_notes/list_history 拿到现状, 在此基础上修改后把完整数组传回来 "
            "(是整体替换, 漏掉的便签会消失!)。notes 和 history 至少传一个, 只传需要改的那个。"
            "执行时便签 app 会自动重启, 屏幕会闪一下; 写入前自动备份为 .bak 文件。"
            "便签字段: id(UUID,可省略自动生成), text, kind(text|todo), theme(lemon|peach|mint|sky|lilac), "
            "mode(floating|normal|desktop), isPreview, isCollapsed, x, y, w, h。"
            "历史字段: id, text, kind, theme, deletedAt(ISO8601)。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "notes": {
                    "type": "array",
                    "items": {"type": "object"},
                    "description": "新的完整便签数组 (不传则不动 notes.json)",
                },
                "history": {
                    "type": "array",
                    "items": {"type": "object"},
                    "description": "新的完整历史数组 (不传则不动 history.json)",
                },
            },
        },
    },
]

NOTE_DEFAULTS = {
    "text": "", "kind": "text", "theme": "lemon", "mode": "floating",
    "isPreview": False, "isCollapsed": False,
    "x": 300.0, "y": 300.0, "w": 280.0, "h": 280.0,
}


def _normalize_note(n):
    if not isinstance(n, dict):
        raise ValueError("notes 数组元素必须是对象")
    out = dict(n)
    if not out.get("id"):
        out["id"] = str(uuid.uuid4()).upper()
    uuid.UUID(out["id"])  # 校验
    for key, default in NOTE_DEFAULTS.items():
        out.setdefault(key, default)
    if out["kind"] not in ("text", "todo"):
        raise ValueError("kind 必须是 text 或 todo")
    if out["theme"] not in ("lemon", "peach", "mint", "sky", "lilac"):
        raise ValueError("theme 非法: {}".format(out["theme"]))
    if out["mode"] not in ("floating", "normal", "desktop"):
        raise ValueError("mode 非法: {}".format(out["mode"]))
    return out


def _normalize_history_item(n):
    if not isinstance(n, dict):
        raise ValueError("history 数组元素必须是对象")
    out = dict(n)
    if not out.get("id"):
        out["id"] = str(uuid.uuid4()).upper()
    uuid.UUID(out["id"])
    out.setdefault("text", "")
    out.setdefault("kind", "text")
    out.setdefault("theme", "lemon")
    out.setdefault("deletedAt",
                   datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"))
    return out


def overwrite_data(args):
    notes = args.get("notes")
    history = args.get("history")
    if notes is None and history is None:
        raise ValueError("notes 和 history 至少要传一个")

    writes = {}
    if notes is not None:
        writes["notes.json"] = [_normalize_note(n) for n in notes]
    if history is not None:
        writes["history.json"] = [_normalize_history_item(n) for n in history]

    # 先退出 app, 避免它的自动保存覆盖我们的写入
    subprocess.run(["pkill", "-x", "StickyNotes"], timeout=10)
    time.sleep(0.8)

    os.makedirs(DATA_DIR, exist_ok=True)
    for filename, data in writes.items():
        path = os.path.join(DATA_DIR, filename)
        if os.path.exists(path):
            shutil.copy2(path, path + ".bak")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    subprocess.run(["open", APP_PATH], check=True, timeout=10)
    return "已重写 {} 并重启 app (原文件备份为 .bak)".format("、".join(writes))


def _encode(params):
    # 必须用 %20 编码空格; 默认的 + 号 app 端不会还原成空格
    return urllib.parse.urlencode(params, quote_via=urllib.parse.quote)


def create_note(args):
    params = {"kind": args.get("kind", "text"), "text": args.get("text", "")}
    if args.get("theme"):
        params["theme"] = args["theme"]
    if args.get("mode"):
        params["mode"] = args["mode"]
    if args.get("preview"):
        params["preview"] = "1"
    if args.get("collapsed"):
        params["collapsed"] = "1"
    url = "stickynotes://add?" + _encode(params)
    subprocess.run(["open", url], check=True, timeout=10)
    return "已创建便签: kind={}, {} 字".format(params["kind"], len(params["text"]))


def update_note(args):
    params = {"id": args.get("id", ""), "text": args.get("text", "")}
    if args.get("theme"):
        params["theme"] = args["theme"]
    url = "stickynotes://update?" + _encode(params)
    subprocess.run(["open", url], check=True, timeout=10)
    return "已更新便签 {}".format(params["id"])


def _load(filename):
    path = os.path.join(DATA_DIR, filename)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def list_notes(_args):
    notes = _load("notes.json")
    if not notes:
        return "当前没有便签。"
    lines = []
    for i, n in enumerate(notes):
        lines.append(
            "--- 便签 {} [id={} | {}|{}{}{}] ---\n{}".format(
                i + 1,
                n.get("id", "?"),
                n.get("kind", "text"),
                n.get("theme", ""),
                "|已折叠" if n.get("isCollapsed") else "",
                "|贴桌面" if n.get("mode") == "desktop" else "",
                n.get("text", ""),
            )
        )
    return "\n".join(lines)


def list_history(_args):
    items = _load("history.json")
    if not items:
        return "历史归档为空。"
    lines = []
    for n in items:
        lines.append(
            "--- {} 删除 [{}] ---\n{}".format(
                n.get("deletedAt", "?"), n.get("kind", "text"), n.get("text", "")
            )
        )
    return "\n".join(lines)


HANDLERS = {
    "create_note": create_note,
    "update_note": update_note,
    "list_notes": list_notes,
    "list_history": list_history,
    "overwrite_data": overwrite_data,
}


def reply(msg_id, result=None, error=None):
    resp = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        resp["error"] = error
    else:
        resp["result"] = result
    sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        method = msg.get("method", "")
        msg_id = msg.get("id")

        if msg_id is None:
            continue  # 通知类消息 (如 notifications/initialized) 不需要回复

        if method == "initialize":
            reply(msg_id, {
                "protocolVersion": msg.get("params", {}).get(
                    "protocolVersion", "2024-11-05"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "stickynotes", "version": "1.0.0"},
            })
        elif method == "tools/list":
            reply(msg_id, {"tools": TOOLS})
        elif method == "tools/call":
            params = msg.get("params", {})
            name = params.get("name")
            handler = HANDLERS.get(name)
            if handler is None:
                reply(msg_id, error={"code": -32602, "message": "未知工具: {}".format(name)})
                continue
            try:
                text = handler(params.get("arguments", {}))
                reply(msg_id, {"content": [{"type": "text", "text": text}], "isError": False})
            except Exception as e:
                reply(msg_id, {"content": [{"type": "text", "text": "执行失败: {}".format(e)}],
                               "isError": True})
        elif method == "ping":
            reply(msg_id, {})
        else:
            reply(msg_id, error={"code": -32601, "message": "不支持的方法: {}".format(method)})


if __name__ == "__main__":
    main()
