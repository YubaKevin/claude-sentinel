#!/usr/bin/env python3
"""Validate only the task-owned installer volume, without reading user settings."""
import os
import pathlib
import re
import subprocess
import sys
from ds_store import DSStore

root=pathlib.Path(sys.argv[1])
if root.parent != pathlib.Path('/Volumes') or root.name != 'Claude Sentinel':
    raise SystemExit('Unexpected installer volume')
expected={
    '.DS_Store','.VolumeIcon.icns','.metadata_never_index','.fseventsd/no_log',
    '.background/space-station.png','ClaudeSentinel.app/Contents/Info.plist',
    'ClaudeSentinel.app/Contents/MacOS/ClaudeSentinel',
    'ClaudeSentinel.app/Contents/Resources/AppIcon.icns',
    'ClaudeSentinel.app/Contents/_CodeSignature/CodeResources',
}
found=set()
for directory,dirs,files in os.walk(root,followlinks=False):
    for name in list(dirs)+list(files):
        path=pathlib.Path(directory)/name
        relative=path.relative_to(root).as_posix()
        if path.is_symlink():
            if relative!='Applications' or os.readlink(path)!='/Applications':
                raise SystemExit('Unexpected installer symlink')
            if name in dirs:dirs.remove(name)
        elif path.is_file():
            found.add(relative)
            data=path.read_bytes()
            home=str(pathlib.Path.home())
            markers=[home.encode(),home.encode('utf-16-be'),home.encode('utf-16-le')]
            if any(marker in data for marker in markers):raise SystemExit('Personal home path in installer payload')
            if re.search(rb'gh[pousr]_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',data):
                raise SystemExit('Credential-like content in installer payload')
if found!=expected:
    raise SystemExit('Unexpected installer files: '+repr(sorted(found.symmetric_difference(expected))))
if not (root/'Applications').is_symlink():raise SystemExit('Applications drop target missing')
with DSStore.open(str(root/'.DS_Store'),'r') as store:
    names={entry.filename for entry in store}
    if names!={'.','ClaudeSentinel.app','Applications'}:raise SystemExit('Unexpected Finder layout records')
    if store['ClaudeSentinel.app']['Iloc']!=(185,232) or store['Applications']['Iloc']!=(535,232):
        raise SystemExit('Incorrect drag target layout')
subprocess.run(['/usr/bin/codesign','--verify','--strict',str(root/'ClaudeSentinel.app')],check=True)
print('PASS: installer file allowlist, drop target, Finder layout, signature and private-path/credential scan')
