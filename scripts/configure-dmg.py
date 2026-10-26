#!/usr/bin/env python3
"""Create only installer view metadata; never copy a Finder .DS_Store."""
import pathlib
import sys
from ds_store import DSStore
from mac_alias import Alias

volume=pathlib.Path(sys.argv[1])
if volume.parent != pathlib.Path('/Volumes') or volume.name != 'Claude Sentinel':
    raise SystemExit('Expected the dedicated installer volume')
background=volume/'.background/space-station.png'
alias=Alias.for_file(str(background)).to_bytes()
# The alias is created on the mounted image, never from a builder's home directory.
if b'/Users/' in alias or '/Users/'.encode('utf-16-be') in alias:
    raise SystemExit('Personal path in background alias')
with DSStore.open(str(volume/'.DS_Store'),'w+') as store:
    store['.']['bwsp']={
        'ShowStatusBar':False,'ShowTabView':False,'ShowToolbar':False,
        'ShowPathbar':False,'ShowSidebar':False,'SidebarWidth':0,
        'WindowBounds':'{{180, 160}, {720, 480}}',
    }
    store['.']['icvp']={
        'viewOptionsVersion':1,'backgroundType':2,'backgroundImageAlias':alias,
        'backgroundColorRed':0.067,'backgroundColorGreen':0.094,'backgroundColorBlue':0.153,
        'gridOffsetX':0.0,'gridOffsetY':0.0,'gridSpacing':100.0,'iconSize':112.0,
        'textSize':13.0,'labelOnBottom':True,'showIconPreview':True,
        'showItemInfo':False,'arrangeBy':'none',
    }
    store['.']['vstl']=('type',b'icnv')
    store['ClaudeSentinel.app']['Iloc']=(185,232)
    store['Applications']['Iloc']=(535,232)
print('Installer layout created without desktop history')
