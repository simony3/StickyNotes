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
import plistlib
import shutil
import subprocess
import sys
import time
import urllib.parse
import uuid

DATA_DIR = os.path.expanduser("~/Library/Application Support/StickyNotes")
APP_PATH = "/Applications/StickyNotes.app"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ACK_TIMEOUT = 8.0  # App 没在运行时 open 要先把它启动起来
SUPPORTED_PROTOCOLS = ("2025-06-18", "2025-03-26", "2024-11-05")
COORDS_NOTE = ("坐标是 macOS 屏幕坐标: 原点在主屏左下角, y 轴向上, "
               "x/y 指窗口左下角, 单位 pt。")
ADMIN_ENABLED = os.environ.get("STICKYNOTES_ENABLE_ADMIN_TOOLS") == "1"

BASE_TOOLS = [
    {
        "name": "create_note",
        "description": (
            "在用户的 macOS 桌面上创建一张便签。text 为便签内容; "
            "待办便签 (kind=todo) 每行一条任务, 用 '[ ] ' 开头表示未完成, '[x] ' 表示已完成; "
            "文字便签 (kind=text) 支持 Markdown (# 标题 / - 列表 / > 引用等)。"
            "创建多张便签就多次调用本工具。返回新便签的 id, 可直接用于后续修改。"
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
                    "description": "true 则以预览模式打开: 文字便签渲染 Markdown, 待办便签为只读视图 (隐藏输入行)",
                },
                "collapsed": {
                    "type": "boolean",
                    "description": "true 则折叠成一行标题条",
                },
                "highlight": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": (
                        "要涂荧光笔的词句, 必须是 text 里原样出现的片段; "
                        "同一个词出现几次就标几次。别整段整段地标, 只标重点。"
                    ),
                },
                "bold": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "要加粗的词句, 规则同 highlight",
                },
            },
            "required": ["text", "kind"],
        },
    },
    {
        "name": "update_note",
        "description": (
            "修改指定便签的内容、颜色、窗口模式、预览或折叠状态, 也可以重设荧光/加粗标记。"
            "先用 list_notes 取得 id；只传需要改的字段。text 是完整替换，不是追加。"
            "只是勾选/增删待办条目时请用 update_todos, 它不会覆盖用户在其他条目上的修改。"
            "只改 text 时会尽量把原有标记按文字内容找回来。"
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
                "preview": {
                    "type": "boolean",
                    "description": "是否预览: 文字便签渲染 Markdown, 待办便签为只读视图 (隐藏输入行)",
                },
                "collapsed": {"type": "boolean", "description": "是否折叠"},
                "highlight": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": (
                        "重设荧光笔标记: 传入要涂的词句 (便签正文里原样出现的片段), "
                        "整体替换原有荧光标记; 传空数组 [] 表示清空全部荧光。"
                    ),
                },
                "bold": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "重设加粗标记, 规则同 highlight; [] 表示取消全部加粗",
                },
            },
            "required": ["id"],
            "anyOf": [
                {"required": ["text"]}, {"required": ["theme"]},
                {"required": ["mode"]}, {"required": ["preview"]},
                {"required": ["collapsed"]}, {"required": ["highlight"]},
                {"required": ["bold"]},
            ],
        },
    },
    {
        "name": "list_notes",
        "description": (
            "列出用户当前屏幕上的所有便签, 含 id (供 update_note 使用)、内容、类型、"
            "颜色、折叠状态、窗口位置尺寸, 以及用户涂过荧光笔和加粗的词句。" + COORDS_NOTE
        ),
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "list_history",
        "description": "列出已删除归档的历史便签 (从新到旧)，含可用于恢复或彻底删除的 id。",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "只列出内容包含该关键词的记录 (不区分大小写)"},
                "limit": {"type": "integer", "minimum": 1, "maximum": 200,
                          "description": "最多返回几条, 默认 20"},
            },
        },
    },
    {
        "name": "update_todos",
        "description": (
            "逐条修改待办便签: 打勾、取消打勾、删除、追加条目。条目按文字点名: "
            "优先找完全相同的, 否则要求只有一条包含该文字 (不区分大小写)。"
            "只动点到的条目, 不会覆盖用户在其他条目上的修改, 比用 update_note 整段重写更安全。"
            "返回修改后的完整条目列表。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "待办便签 id"},
                "check": {"type": "array", "items": {"type": "string"}, "description": "要打勾的条目"},
                "uncheck": {"type": "array", "items": {"type": "string"}, "description": "要取消打勾的条目"},
                "remove": {"type": "array", "items": {"type": "string"}, "description": "要删除的条目"},
                "add": {"type": "array", "items": {"type": "string"}, "description": "追加到末尾的新条目"},
            },
            "required": ["id"],
            "anyOf": [
                {"required": ["check"]}, {"required": ["uncheck"]},
                {"required": ["remove"]}, {"required": ["add"]},
            ],
        },
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
        "description": (
            "移动或调整指定便签的窗口大小，只传需要改的坐标/尺寸。" + COORDS_NOTE +
            "待办便签默认按内容自动定大小，传了 width/height 后该方向改为固定值，"
            "传 auto_size=true 恢复自动。尺寸小于 App 允许的最小值时按最小值处理。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "id": {"type": "string", "description": "便签 id"},
                "x": {"type": "number", "description": "窗口左下角 x"},
                "y": {"type": "number", "description": "窗口左下角 y (向上为正)"},
                "width": {"type": "number", "minimum": 120},
                "height": {"type": "number", "minimum": 30},
                "auto_size": {
                    "type": "boolean",
                    "description": "true 则恢复待办便签按内容自动定大小, 不能和 width/height 同时传",
                },
            },
            "required": ["id"],
            "anyOf": [
                {"required": ["x"]}, {"required": ["y"]},
                {"required": ["width"]}, {"required": ["height"]},
                {"required": ["auto_size"]},
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
                   datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
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


def _u16len(s):
    """便签里的标记范围按 UTF-16 存 (和 NSRange 一致), emoji 算两格。"""
    return len(s.encode("utf-16-le")) // 2


def _u16slice(s, location, length):
    raw = s.encode("utf-16-le")[location * 2:(location + length) * 2]
    return raw.decode("utf-16-le", "ignore")


def _mark_ranges(text, needles, label):
    """把要标记的词换算成 UTF-16 范围。同一个词出现几次就标几次。"""
    if isinstance(needles, str):
        needles = [needles]
    if not isinstance(needles, list):
        raise ValueError("{} 必须是字符串数组".format(label))
    out, missing = [], []
    for needle in needles:
        if not isinstance(needle, str):
            raise ValueError("{} 的每一项都必须是字符串".format(label))
        if not needle:
            continue
        start, found = 0, False
        while True:
            i = text.find(needle, start)
            if i < 0:
                break
            out.append((_u16len(text[:i]), _u16len(needle)))
            start = i + len(needle)
            found = True
        if not found:
            missing.append(needle)
    return out, missing


def _encode_marks(ranges):
    return ";".join("{},{}".format(loc, length) for loc, length in ranges)


def _find_all(text, piece):
    """不重叠地找出 piece 每次出现的位置 (Python 下标), 和 _mark_ranges 的找法一致。"""
    hits, start = [], 0
    while True:
        i = text.find(piece, start)
        if i < 0:
            return hits
        hits.append(i)
        start = i + len(piece)


def _carry_marks(old_text, old_marks, new_text):
    """整段替换后按「原文标的是哪几个字、是第几处」在新文里找回来, 找不到的就丢掉。"""
    out = []
    for m in old_marks or []:
        try:
            location, length = int(m["location"]), int(m["length"])
        except (KeyError, TypeError, ValueError):
            continue
        piece = _u16slice(old_text, location, length)
        hits = _find_all(new_text, piece) if piece else []
        if not hits:
            continue
        nth = sum(1 for i in _find_all(old_text, piece) if _u16len(old_text[:i]) < location)
        i = hits[min(nth, len(hits) - 1)]
        r = (_u16len(new_text[:i]), _u16len(piece))
        if r not in out:
            out.append(r)
    return out


def _find_in(filename, item_id):
    for n in _load(filename):
        if str(n.get("id", "")).lower() == item_id.lower():
            return n
    return None


def _require_note(value):
    note = _find_in("notes.json", _validate_id(value))
    if note is None:
        raise ValueError("找不到便签 {}，请先用 list_notes 确认 id".format(value))
    return note


def _require_history(value):
    item = _find_in("history.json", _validate_id(value, "历史 id"))
    if item is None:
        raise ValueError("找不到历史记录 {}，请先用 list_history 确认 id".format(value))
    return item


def _todo_items(text):
    """和 App 的 Note.todoItems 同一套解析: 每个非空行一条, [x]/[ ] 前缀表示完成状态。"""
    items = []
    for line in text.split("\n"):
        t = line.strip(" \t")
        if not t:
            continue
        if t.startswith(("[x] ", "[X] ")):
            items.append((t[4:], True))
        elif t.startswith("[ ] "):
            items.append((t[4:], False))
        else:
            items.append((t, False))
    return items


def _todo_match_problem(items, needle):
    """和 App 的 Note.todoIndex(matching:) 同一套规则, 能唯一点名时返回 None。"""
    if any(text == needle for text, _ in items):
        return None
    hits = [text for text, _ in items if needle.lower() in text.lower()]
    if len(hits) == 1:
        return None
    if not hits:
        return "没找到「{}」".format(needle)
    return "「{}」匹配到多条: {}".format(needle, "、".join(hits))


def _format_todos(items):
    if not items:
        return "(没有条目)"
    return "\n".join("{}. [{}] {}".format(i + 1, "x" if done else " ", text)
                     for i, (text, done) in enumerate(items))


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


def _read_ack():
    try:
        with open(os.path.join(DATA_DIR, "mcp-ack"), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def _open_command(host, params=None):
    """把命令交给 App 并等回执: App 处理完会先落盘, 再把 ack 写进 mcp-ack,
    所以回执到了之后读到的 notes.json / history.json 一定是最新的。"""
    ack = uuid.uuid4().hex
    pairs = list(params.items() if isinstance(params, dict) else params or [])
    url = "stickynotes://{}?{}".format(host, _encode(pairs + [("ack", ack)]))
    try:
        subprocess.run(["open", url], check=True, timeout=10, capture_output=True)
    except subprocess.CalledProcessError:
        if not os.path.exists(APP_PATH):
            raise RuntimeError("没找到 {}，请先在项目目录运行 ./build.sh 安装 App".format(APP_PATH))
        raise RuntimeError("无法把命令交给 StickyNotes App")
    deadline = time.monotonic() + ACK_TIMEOUT
    while time.monotonic() < deadline:
        if _read_ack() == ack:
            return
        time.sleep(0.05)
    raise RuntimeError(
        "StickyNotes 没有在 {:.0f} 秒内确认这次操作, 可能卡在弹窗里或未响应".format(ACK_TIMEOUT))


def create_note(args):
    note_id = str(uuid.uuid4()).upper()
    params = {"id": note_id, "kind": args.get("kind", "text"), "text": args.get("text", "")}
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

    notes = []
    for field, url_key, label in (("highlight", "highlight", "荧光标记"),
                                  ("bold", "bold", "加粗")):
        if field not in args:
            continue
        ranges, missing = _mark_ranges(params["text"], args[field], field)
        params[url_key] = _encode_marks(ranges)
        if ranges:
            notes.append("{} {} 处".format(label, len(ranges)))
        if missing:
            notes.append("{}没找到: {}".format(label, "、".join(missing)))

    _open_command("add", params)
    if _find_in("notes.json", note_id) is None:
        raise RuntimeError("App 已响应但没有生成便签, 请用 list_notes 检查")
    summary = "已创建便签 id={}, kind={}, {} 字".format(note_id, params["kind"], len(params["text"]))
    return summary + ("; " + "; ".join(notes) if notes else "")


def update_note(args):
    fields = ("text", "theme", "mode", "preview", "collapsed", "highlight", "bold")
    if not any(field in args for field in fields):
        raise ValueError("至少传入一个需要修改的字段")
    current = _require_note(args.get("id"))
    params = {"id": current["id"]}
    old_text = current.get("text", "")
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

    # 换了正文又没指定标记时, 按原来标的是哪几个字在新文里找回来,
    # 免得 AI 改一句话就把用户涂的荧光和加粗全弄丢。
    text_now = params.get("text", old_text)
    notes = []
    for field, store_key, label in (("highlight", "highlights", "荧光标记"),
                                    ("bold", "bolds", "加粗")):
        if field in args:
            ranges, missing = _mark_ranges(text_now, args[field], field)
            params[field] = _encode_marks(ranges)
            if missing:
                notes.append("{}没找到: {}".format(label, "、".join(missing)))
        elif "text" in args:
            carried = _carry_marks(old_text, current.get(store_key), text_now)
            if carried or current.get(store_key):
                params[field] = _encode_marks(carried)
                kept, total = len(carried), len(current.get(store_key) or [])
                if total:
                    notes.append("{}保留 {}/{} 处".format(label, kept, total))

    _open_command("update", params)
    after = _require_note(params["id"])
    if "text" in args and after.get("text") != params["text"]:
        notes.append("注意: 正文和传入的不一致, 用户可能正在同时编辑这张便签")
    return "已更新便签 {}".format(params["id"]) + ("; " + "; ".join(notes) if notes else "")


def update_todos(args):
    note = _require_note(args.get("id"))
    if note.get("kind") != "todo":
        raise ValueError("便签 {} 不是待办便签, 请用 update_note 修改".format(note["id"]))
    ops = []
    for field in ("check", "uncheck", "remove", "add"):
        values = args.get(field, [])
        if not isinstance(values, list) or not all(isinstance(v, str) for v in values):
            raise ValueError("{} 必须是字符串数组".format(field))
        ops += [(field, v.strip()) for v in values if v.strip()]
    if not ops:
        raise ValueError("check、uncheck、remove、add 至少传一个非空条目")

    items = _todo_items(note.get("text", ""))
    problems = [p for field, v in ops if field != "add"
                for p in [_todo_match_problem(items, v)] if p]
    if problems:
        raise ValueError("；".join(problems) + "。当前条目:\n" + _format_todos(items))

    _open_command("todo", [("id", note["id"])] + ops)
    after = _require_note(note["id"])
    return "已更新待办 {}:\n{}".format(note["id"], _format_todos(_todo_items(after.get("text", ""))))


def delete_note(args):
    note_id = _require_note(args.get("id"))["id"]
    _open_command("delete", {"id": note_id})
    if _find_in("notes.json", note_id) is not None:
        raise RuntimeError("App 已响应但便签还在, 请用 list_notes 检查")
    return "已删除便签 {}（非空内容已归档）".format(note_id)


def move_resize_note(args):
    params = {"id": _require_note(args.get("id"))["id"]}
    mapping = {"x": "x", "y": "y", "width": "w", "height": "h"}
    auto = args.get("auto_size")
    if auto is not None and not isinstance(auto, bool):
        raise ValueError("auto_size 必须是布尔值")
    if not auto and not any(key in args for key in mapping):
        raise ValueError("至少传入 x、y、width、height、auto_size 之一")
    if auto and ("width" in args or "height" in args):
        raise ValueError("auto_size 不能和 width/height 同时传")
    if auto:
        params["auto"] = "1"
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
    n = _require_note(params["id"])
    return "已移动/调整便签 {}: x={}, y={}, width={}, height={}{}".format(
        params["id"], n.get("x"), n.get("y"), n.get("w"), n.get("h"),
        " (已恢复自动适配, 窗口会随内容调整)" if auto else "")


def restore_note(args):
    item_id = _require_history(args.get("id"))["id"]
    _open_command("restore", {"id": item_id})
    if _find_in("history.json", item_id) is not None:
        raise RuntimeError("App 已响应但历史记录还在, 请用 list_history 检查")
    return "已恢复历史便签 {}".format(item_id)


def delete_history_item(args):
    item_id = _require_history(args.get("id"))["id"]
    _open_command("history-delete", {"id": item_id})
    if _find_in("history.json", item_id) is not None:
        raise RuntimeError("App 已响应但历史记录还在, 请用 list_history 检查")
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
        text = n.get("text", "")
        marks = ""
        for key, label in (("highlights", "荧光"), ("bolds", "加粗")):
            pieces = [_u16slice(text, m.get("location", 0), m.get("length", 0))
                      for m in n.get(key) or []]
            pieces = [p for p in pieces if p]
            if pieces:
                marks += "{}: {}\n".format(label, "、".join(pieces))
        if n.get("kind") == "todo":
            marks += "尺寸: 宽{} 高{}\n".format(
                "固定" if n.get("mw") else "自动", "固定" if n.get("mh") else "自动")
        lines.append(
            "--- 便签 {} ---\n"
            "id={} | kind={} | theme={} | mode={} | preview={} | collapsed={}\n"
            "frame: x={}, y={}, width={}, height={}\n{}{}".format(
                i + 1,
                n.get("id", "?"),
                n.get("kind", "text"),
                n.get("theme", ""),
                n.get("mode", "floating"),
                bool(n.get("isPreview")),
                bool(n.get("isCollapsed")),
                n.get("x", "?"), n.get("y", "?"),
                n.get("w", "?"), n.get("h", "?"),
                marks,
                text,
            )
        )
    return "\n".join(lines)


def list_history(args):
    items = _load("history.json")
    query = args.get("query")
    limit = args.get("limit", 20)
    if query is not None and not isinstance(query, str):
        raise ValueError("query 必须是字符串")
    if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 200:
        raise ValueError("limit 必须是 1~200 的整数")
    if query:
        items = [n for n in items if query.lower() in n.get("text", "").lower()]
    if not items:
        return "没有包含「{}」的历史便签。".format(query) if query else "历史归档为空。"
    lines = ["共 {} 条{}，显示最近 {} 条".format(
        len(items), "匹配" if query else "", min(limit, len(items)))]
    for n in items[:limit]:
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
    "update_todos": update_todos,
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


def _server_version():
    try:
        with open(os.path.join(SCRIPT_DIR, "..", "Resources", "Info.plist"), "rb") as f:
            return plistlib.load(f).get("CFBundleShortVersionString", "unknown")
    except (OSError, plistlib.InvalidFileException):
        return "unknown"


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
            requested = msg.get("params", {}).get("protocolVersion")
            reply(msg_id, {
                "protocolVersion": requested if requested in SUPPORTED_PROTOCOLS
                else SUPPORTED_PROTOCOLS[0],
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "stickynotes", "version": _server_version()},
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
