#!/usr/bin/env python3
import json, os
from pathlib import Path
from urllib.parse import unquote

def get_workspaces():
    storage_path = Path.home() / '.config/Code/User/globalStorage/storage.json'
    data = json.loads(storage_path.read_text())

    seen = set()
    entries = []

    def add(uri):
        if not uri or uri in seen:
            return
        seen.add(uri)
        decoded = unquote(uri)
        if decoded.startswith('file://'):
            path = Path(decoded[7:])
            name = path.stem.removesuffix('.code-workspace')
            label = name
        else:
            rest = decoded.split('://', 1)[1]
            authority, _, path_part = rest.partition('/')
            remote = authority.split('+', 1)[-1] if '+' in authority else authority
            name = Path(path_part).stem.removesuffix('.code-workspace')
            label = f"{name}  [{remote}]"
        entries.append((label, uri))

    bw = data.get('backupWorkspaces', {})
    for ws in bw.get('workspaces', []):
        add(ws.get('configURIPath'))
    for folder in bw.get('folders', []):
        add(folder.get('folderUri'))

    ws_state = data.get('windowsState', {})
    for w in [ws_state.get('lastActiveWindow', {})] + ws_state.get('openedWindows', []):
        add(w.get('workspaceIdentifier', {}).get('configURIPath'))
        add(w.get('folder') or w.get('folderUri'))

    return entries

retv = int(os.environ.get('ROFI_RETV', '0'))

if retv == 0:
    for label, uri in get_workspaces():
        print(f"{label}\0icon\x1fvscode\x1finfo\x1f{uri}")
elif retv == 1:
    uri = os.environ.get('ROFI_INFO', '')
    if uri:
        os.execvp('code', ['code', '--folder-uri', uri])
