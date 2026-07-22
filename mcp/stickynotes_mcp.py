#!/usr/bin/env python3
"""StickyNotes MCP 服务器 (stdio, 零依赖)

日常工具通过 stickynotes:// 把细粒度命令交给 App 执行，App 是唯一的
数据写入者，因此增删改、窗口模式、折叠、移动和历史恢复都无需重启。

直接整体导入 JSON 的管理员工具默认不暴露；只有显式设置
STICKYNOTES_ENABLE_ADMIN_TOOLS=1 时才能使用。
"""
import datetime
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import time
import urllib.parse
import uuid

DATA_DIR = os.path.expanduser("~/Library/Application Support/StickyNotes")
APP_PATH = "/Applications/StickyNotes.app"
ADMIN_ENABLED = os.environ.get("STICKYNOTES_ENABLE_ADMIN_TOOLS") == "1"

BASE_TOOLS = [
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
            "修改指定便签的内容、颜色、窗口模式、预览或折叠状态。"
            "先用 list_notes 取得 id；只传需要改的字段。text 是完整替换，不是追加。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "便签 id (从 list_notes 获取)"},
                "text": {"type": "string", "description": "新的完整内容, 整体替换"},
                "theme": {
                    "type": "string",
                    "enum": ["lemon", "peach", "mint", "sky", "lilac"],
                    "description": "新颜色",
                },
                "mode": {
                    "type": "string",
                    "enum": ["floating", "normal", "desktop"],
                    "description": "窗口模式",
                },
                "preview": {"type": "boolean", "description": "是否预览 Markdown"},
                "collapsed": {"type": "boolean", "description": "是否折叠"},
            },
            "required": ["id"],
            "anyOf": [
                {"required": ["text"]}, {"required": ["theme"]},
                {"required": ["mode"]}, {"required": ["preview"]},
                {"required": ["collapsed"]},
            ],
        },
    },
    {
        "name": "list_notes",
        "description": "列出用户当前屏幕上的所有便签, 含 id (供 update_note 使用)、内容、类型、颜色、折叠状态。",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "list_history",
        "description": "列出已删除归档的历史便签，含可用于恢复或彻底删除的 id。",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "delete_note",
        "description": "删除指定便签。非空便签会进入历史归档，仍可恢复。",
        "inputSchema": {
            "type": "object",
            "properties": {"id": {"type": "string", "description": "便签 id"}},
            "required": ["id"],
        },
    },
    {
        "name": "move_resize_note",
        "description": "移动或调整指定便签的窗口大小，只传需要改的坐标/尺寸。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "便签 id"},
                "x": {"type": "number"}, "y": {"type": "number"},
                "width": {"type": "number", "minimum": 120},
                "height": {"type": "number", "minimum": 30},
            },
            "required": ["id"],
            "anyOf": [
                {"required": ["x"]}, {"required": ["y"]},
                {"required": ["width"]}, {"required": ["height"]},
            ],
        },
    },
    {
        "name": "restore_note",
        "description": "将一条历史归档恢复成新便签。先用 list_history 取得历史 id。",
        "inputSchema": {
            "type": "object",
            "properties": {"id": {"type": "string", "description": "历史记录 id"}},
            "required": ["id"],
        },
    },
    {
        "name": "delete_history_item",
        "description": "彻底删除指定历史记录，删除后无法从 App 恢复。",
        "inputSchema": {
            "type": "object",
            "properties": {"id": {"type": "string", "description": "历史记录 id"}},
            "required": ["id"],
        },
    },
    {
        "name": "show_all_notes",
        "description": "将所有便签窗口带到前面。",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "show_history",
        "description": "打开 StickyNotes 的历史便签窗口。",
        "inputSchema": {"type": "object", "properties": {}},
    },
]

ADMIN_TOOLS = [
    {
        "name": "admin_export_data",
        "description": "管理员工具：导出完整 JSON 和数据版本，供批量迁移前审查。",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "admin_overwrite_data",
        "description": (
            "管理员工具：整体导入便签或历史数据。仅用于批量迁移/灾难恢复；"
            "必须提供 admin_export_data 返回的 expected_revision 并显式 confirm=true。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "expected_revision": {"type": "string"},
                "confirm": {"type": "boolean"},
                "notes": {"type": "array", "items": {"type": "object"}},
                "history": {"type": "array", "items": {"type": "object"}},
            },
            "required": ["expected_revision", "confirm"],
        },
    },
]

TOOLS = BASE_TOOLS + (ADMIN_TOOLS if ADMIN_ENABLED else [])

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


def _data_revision():
    """对两个数据文件生成稳定版本号，防止用旧快照覆盖用户的新编辑。"""
    digest = hashlib.sha256()
    for filename in ("notes.json", "history.json"):
        path = os.path.join(DATA_DIR, filename)
        digest.update(filename.encode("utf-8") + b"\0")
        if os.path.exists(path):
            with open(path, "rb") as f:
                digest.update(f.read())
        else:
            digest.update(b"<missing>")
    return digest.hexdigest()


def admin_export_data(_args):
    return json.dumps({
        "revision": _data_revision(),
        "notes": _load("notes.json"),
        "history": _load("history.json"),
    }, ensure_ascii=False, indent=2)


def _backup(path):
    if not os.path.exists(path):
        return
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = "{}.bak.{}".format(path, stamp)
    shutil.copy2(path, backup)
    prefix = os.path.basename(path) + ".bak."
    backups = sorted(
        os.path.join(DATA_DIR, name)
        for name in os.listdir(DATA_DIR)
        if name.startswith(prefix)
    )
    for old in backups[:-10]:
        os.remove(old)


def _atomic_write_json(path, data):
    temp = "{}.tmp.{}".format(path, uuid.uuid4().hex)
    try:
        with open(temp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.remove(temp)


def admin_overwrite_data(args):
    if not ADMIN_ENABLED:
        raise PermissionError("管理员工具未启用")
    if args.get("confirm") is not True:
        raise ValueError("必须显式传入 confirm=true")
    expected = args.get("expected_revision", "")
    if not expected or expected != _data_revision():
        raise ValueError("数据版本已变化，请重新调用 admin_export_data 后再操作")

    notes = args.get("notes")
    history = args.get("history")
    if notes is None and history is None:
        raise ValueError("notes 和 history 至少要传一个")

    writes = {}
    if notes is not None:
        writes["notes.json"] = [_normalize_note(n) for n in notes]
    if history is not None:
        writes["history.json"] = [_normalize_history_item(n) for n in history]

    # 只有管理员批量导入才需要暂停 App。停止后再校验一次版本，
    # 因为 App 在退出时可能刚好落盘了最后一次编辑。
    was_running = subprocess.run(
        ["pgrep", "-x", "StickyNotes"], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, timeout=10).returncode == 0
    if was_running:
        subprocess.run(["pkill", "-x", "StickyNotes"], check=False, timeout=10)
        time.sleep(0.8)

    try:
        if expected != _data_revision():
            raise ValueError("App 退出时保存了新数据，本次导入已取消；请重新导出")
        os.makedirs(DATA_DIR, exist_ok=True)
        for filename, data in writes.items():
            path = os.path.join(DATA_DIR, filename)
            _backup(path)
            _atomic_write_json(path, data)
    finally:
        if was_running:
            subprocess.run(["open", APP_PATH], check=True, timeout=10)

    return "已导入 {}，原文件已作时间戳备份（最多保留 10 份）".format("、".join(writes))


def _encode(params):
    # 必须用 %20 编码空格; 默认的 + 号 app 端不会还原成空格
    return urllib.parse.urlencode(params, quote_via=urllib.parse.quote)


def _validate_id(value, label="id"):
    if not value:
        raise ValueError("缺少 {}".format(label))
    try:
        return str(uuid.UUID(value))
    except (ValueError, AttributeError, TypeError):
        raise ValueError("{} 必须是有效 UUID".format(label))


def _validate_choice(value, choices, label):
    if value not in choices:
        raise ValueError("{} 非法: {}".format(label, value))


def _open_command(host, params=None):
    url = "stickynotes://{}".format(host)
    if params:
        url += "?" + _encode(params)
    subprocess.run(["open", url], check=True, timeout=10)


def create_note(args):
    params = {"kind": args.get("kind", "text"), "text": args.get("text", "")}
    _validate_choice(params["kind"], ("text", "todo"), "kind")
    if not isinstance(params["text"], str):
        raise ValueError("text 必须是字符串")
    if args.get("theme") is not None:
        _validate_choice(args["theme"], ("lemon", "peach", "mint", "sky", "lilac"), "theme")
        params["theme"] = args["theme"]
    if args.get("mode") is not None:
        _validate_choice(args["mode"], ("floating", "normal", "desktop"), "mode")
        params["mode"] = args["mode"]
    if args.get("preview"):
        params["preview"] = "1"
    if args.get("collapsed"):
        params["collapsed"] = "1"
    _open_command("add", params)
    return "已创建便签: kind={}, {} 字".format(params["kind"], len(params["text"]))


def update_note(args):
    params = {"id": _validate_id(args.get("id"))}
    fields = ("text", "theme", "mode", "preview", "collapsed")
    if not any(field in args for field in fields):
        raise ValueError("至少传入一个需要修改的字段")
    if "text" in args:
        if not isinstance(args["text"], str):
            raise ValueError("text 必须是字符串")
        params["text"] = args["text"]
    if "theme" in args:
        _validate_choice(args["theme"], ("lemon", "peach", "mint", "sky", "lilac"), "theme")
        params["theme"] = args["theme"]
    if "mode" in args:
        _validate_choice(args["mode"], ("floating", "normal", "desktop"), "mode")
        params["mode"] = args["mode"]
    for field in ("preview", "collapsed"):
        if field in args:
            if not isinstance(args[field], bool):
                raise ValueError("{} 必须是布尔值".format(field))
            params[field] = "1" if args[field] else "0"
    _open_command("update", params)
    return "已更新便签 {}".format(params["id"])


def delete_note(args):
    note_id = _validate_id(args.get("id"))
    _open_command("delete", {"id": note_id})
    return "已删除便签 {}（非空内容已归档）".format(note_id)


def move_resize_note(args):
    params = {"id": _validate_id(args.get("id"))}
    mapping = {"x": "x", "y": "y", "width": "w", "height": "h"}
    if not any(key in args for key in mapping):
        raise ValueError("至少传入 x、y、width、height 之一")
    for key, query_key in mapping.items():
        if key not in args:
            continue
        value = args[key]
        if (not isinstance(value, (int, float)) or isinstance(value, bool)
                or not math.isfinite(float(value))):
            raise ValueError("{} 必须是有限数字".format(key))
        if key == "width" and value < 120:
            raise ValueError("width 不能小于 120")
        if key == "height" and value < 30:
            raise ValueError("height 不能小于 30")
        params[query_key] = str(value)
    _open_command("frame", params)
    return "已移动/调整便签 {}".format(params["id"])


def restore_note(args):
    item_id = _validate_id(args.get("id"), "历史 id")
    _open_command("restore", {"id": item_id})
    return "已恢复历史便签 {}".format(item_id)


def delete_history_item(args):
    item_id = _validate_id(args.get("id"), "历史 id")
    _open_command("history-delete", {"id": item_id})
    return "已彻底删除历史记录 {}".format(item_id)


def show_all_notes(_args):
    _open_command("show-all")
    return "已将所有便签带到前面"


def show_history(_args):
    _open_command("show-history")
    return "已打开历史便签窗口"


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
            "--- 便签 {} ---\n"
            "id={} | kind={} | theme={} | mode={} | preview={} | collapsed={}\n"
            "frame: x={}, y={}, width={}, height={}\n{}".format(
                i + 1,
                n.get("id", "?"),
                n.get("kind", "text"),
                n.get("theme", ""),
                n.get("mode", "floating"),
                bool(n.get("isPreview")),
                bool(n.get("isCollapsed")),
                n.get("x", "?"), n.get("y", "?"),
                n.get("w", "?"), n.get("h", "?"),
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
            "--- {} 删除 ---\n"
            "id={} | kind={} | theme={}\n{}".format(
                n.get("deletedAt", "?"), n.get("id", "?"),
                n.get("kind", "text"), n.get("theme", "lemon"), n.get("text", "")
            )
        )
    return "\n".join(lines)


HANDLERS = {
    "create_note": create_note,
    "update_note": update_note,
    "list_notes": list_notes,
    "list_history": list_history,
    "delete_note": delete_note,
    "move_resize_note": move_resize_note,
    "restore_note": restore_note,
    "delete_history_item": delete_history_item,
    "show_all_notes": show_all_notes,
    "show_history": show_history,
}

if ADMIN_ENABLED:
    HANDLERS.update({
        "admin_export_data": admin_export_data,
        "admin_overwrite_data": admin_overwrite_data,
    })


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
                "serverInfo": {"name": "stickynotes", "version": "1.1.0"},
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
