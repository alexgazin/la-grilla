#!/usr/bin/env python3
"""Choose a current iOS runtime, keeping compact capture on the same runtime."""
import argparse,json,os,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--name',required=True);p.add_argument('--type',required=True);p.add_argument('--same-runtime-as');a=p.parse_args()
def query(*args):return json.loads(subprocess.check_output(['xcrun','simctl',*args,'-j'],text=True))
devices=query('list','devices','available')['devices']
if a.same_runtime_as:
 runtime=next(key for key,items in devices.items() if any(x['udid']==a.same_runtime_as for x in items))
else:
 sdk=tuple(map(int,subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-version'],text=True).strip().split('.')))
 candidates=[]
 inventory=query('list','runtimes')
 if path:=os.environ.get('GRILLA_SIMULATOR_RUNTIME_INVENTORY'):
  Path(path).write_text(json.dumps(inventory))
 for item in inventory['runtimes']:
  if not item.get('isAvailable') or '.iOS-' not in item['identifier']:continue
  version=tuple(map(int,item['version'].split('.')))
  if version[0]>=26 and (version+(0,0))[:2]<=(sdk+(0,0))[:2]:candidates.append((version,item['identifier']))
 assert candidates,'An installed iOS 26+ simulator runtime is required for release acceptance'
 runtime=max(candidates)[1]
matches=[x['udid'] for x in devices.get(runtime,[]) if x['name']==a.name]
if matches:print(matches[0])
else:print(subprocess.check_output(['xcrun','simctl','create',a.name,a.type,runtime],text=True).strip())
