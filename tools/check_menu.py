"""Validate the KUAL menu.json structure."""

import json
from pathlib import Path

MENU = Path(r"D:\project\kpw3-frame\kindle\extensions\kpw3-screensaver\menu.json")

data = json.loads(MENU.read_text(encoding="utf-8"))
print("menu.json OK")


def walk(items, depth=0):
    for item in items:
        name = item.get("name", "?")
        if "items" in item:
            print("  " * depth + f"[{name}]")
            walk(item["items"], depth + 1)
        else:
            action = item.get("action", "(none)")
            print("  " * depth + f"{name}   -> {action}")


walk(data["items"])
