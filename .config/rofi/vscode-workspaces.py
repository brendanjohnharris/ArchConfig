#!/usr/bin/env python3
"""rofi script-mode: list recent VS Code workspaces (and optionally folders).

Discovery comes from `lastKnownMenubarData` (the File > Open Recent menu) in
Code's storage.json -- this is the full recent list, not just the currently
open / last-session windows. backupWorkspaces + windowsState are merged in as a
fallback so anything open right now always shows even if the menu cache is stale.

Each entry is opened with the correct flag: a `.code-workspace` file must use
`--file-uri` (this actually *activates* the multi-root workspace); a plain
folder uses `--folder-uri`. Using --folder-uri on a workspace file only reopens
its directory and the last editor, which is the bug this avoids.

Set SHOW_FOLDERS = True to include plain folders in the list.
"""
import json, os
from pathlib import Path
from urllib.parse import unquote, quote


SHOW_FOLDERS = False


def uri_from_component(u):
    """Rebuild a URI string from a VS Code URI component dict (or pass through a str)."""
    if isinstance(u, str):
        return u
    if not isinstance(u, dict):
        return None
    if u.get('external'):
        return u['external']
    scheme = u.get('scheme')
    path = u.get('path', '')
    if not scheme or not path:
        return None
    authority = u.get('authority', '')
    # Match VS Code's own encoding: '+' in the authority is stored as %2B.
    return f"{scheme}://{quote(authority, safe='')}{path}"


def label_for(uri, is_workspace):
    decoded = unquote(uri)
    rest = decoded.split('://', 1)[1] if '://' in decoded else decoded
    if decoded.startswith('file://'):
        path = rest
        remote = None
    else:
        authority, _, path = rest.partition('/')
        path = '/' + path
        remote = authority.split('+', 1)[-1] if '+' in authority else authority
    name = Path(path).name.removesuffix('.code-workspace')
    # Folders are tagged "[<host> folder]" (or "[folder]" locally) so they are
    # distinguishable from the workspace of the same name; workspaces keep the
    # bare "[<host>]" tag (or nothing locally).
    if is_workspace:
        tag = remote
    else:
        tag = f"{remote} folder" if remote else "folder"
    return f"{name}  [{tag}]" if tag else name


def is_workspace_uri(uri):
    return bool(uri) and unquote(uri).endswith('.code-workspace')


def get_entries():
    storage = Path.home() / '.config/Code/User/globalStorage/storage.json'
    data = json.loads(storage.read_text())

    seen = set()
    entries = []  # (label, uri, is_workspace)

    def add(uri):
        if not uri or uri in seen:
            return
        is_ws = is_workspace_uri(uri)
        if not is_ws and not SHOW_FOLDERS:
            return
        seen.add(uri)
        entries.append((label_for(uri, is_ws), uri, is_ws))

    # Recency-ordered head: File > Open Recent menu (~10 most-recent). These are
    # added first so the most recently used workspaces sort to the top.
    menus = data.get('lastKnownMenubarData', {}).get('menus', {})
    for item in menus.get('File', {}).get('items', []):
        if 'Recent' not in item.get('label', ''):
            continue
        for s in item.get('submenu', {}).get('items', []):
            if s.get('id') in ('openRecentWorkspace', 'openRecentFolder'):
                add(uri_from_component(s.get('uri')))

    # Complete set: every workspace/folder VS Code has a profile association for
    # (a superset of the Ctrl+R quick-pick). The menu is capped at 10, so this is
    # what actually fills out the list. Unordered (keyed by URI), hence appended
    # after the recency head above. `__` keys are internal markers, not URIs.
    for uri in data.get('profileAssociations', {}).get('workspaces', {}):
        if '://' in uri:
            add(uri)

    # Fallback: anything open right now / from the last session.
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
    for label, uri, is_ws in get_entries():
        # Stash the open flag with the URI so retv==1 picks the right one.
        flag = '--file-uri' if is_ws else '--folder-uri'
        print(f"{label}\0icon\x1fvscode\x1finfo\x1f{flag} {uri}")
elif retv == 1:
    info = os.environ.get('ROFI_INFO', '')
    if info:
        flag, _, uri = info.partition(' ')
        os.execvp('code', ['code', flag, uri])
