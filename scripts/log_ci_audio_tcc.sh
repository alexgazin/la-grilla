#!/bin/bash
# Diagnostic observations only: never grant/reset permissions or modify TCC.
# Official runner source configures this exact SimulatorTrampoline bundle ID:
# https://github.com/actions/runner-images/blob/95e6f51a068507e8f43d061d2166a39d0ef36ce8/images/macos/scripts/build/configure-tccdb-macos.sh#L82
set -euo pipefail
if [[ $(uname -s) != Darwin ]]; then
  echo "Host microphone authorization diagnostics require macOS." >&2
  exit 1
fi
python3 - <<'PY'
import json,os,pathlib,subprocess

def observe(label,args,timeout=8,include_output=True):
    try:
        result=subprocess.run(args,text=True,capture_output=True,timeout=timeout,check=False)
        print(json.dumps(dict(observation=label,status=result.returncode,stdout=result.stdout.strip() if include_output else '',stderr=result.stderr.strip())))
        return result
    except (OSError,subprocess.TimeoutExpired) as error:
        print(json.dumps(dict(observation=label,error=type(error).__name__)))
        return None

print('Read-only host microphone/TCC observations; no policy mutation or inferred authorization.')
print(json.dumps(dict(imageOS=os.environ.get('ImageOS'),imageVersion=os.environ.get('ImageVersion'),user=os.environ.get('USER'),home=os.environ.get('HOME'))))
observe('macOS build',['/usr/bin/sw_vers'])
observe('console user',['/usr/bin/stat','-f','%Su','/dev/console'])
observe('selected developer directory',['/usr/bin/xcode-select','-p'])
observe('resolved simctl',['/usr/bin/xcrun','--find','simctl'])

# Query only the exact microphone client under investigation. An unreadable DB
# or empty result is logged as such and is not evidence of an allow or denial.
query="SELECT service,client,client_type,auth_value,auth_reason,auth_version,(csreq IS NULL) AS csreq_is_null,last_modified FROM access WHERE service='kTCCServiceMicrophone' AND client='com.apple.CoreSimulator.SimulatorTrampoline';"
for label,path in [('user',pathlib.Path.home()/'Library/Application Support/com.apple.TCC/TCC.db'),('system',pathlib.Path('/Library/Application Support/com.apple.TCC/TCC.db'))]:
    observe(label+' SimulatorTrampoline microphone rows',['/usr/bin/sqlite3','-readonly','-json',str(path),query])

# These are actual running executable paths, not a guessed path under Xcode.
processes=observe('Simulator process discovery',['/bin/ps','-axo','pid=,comm='],include_output=False)
if processes and processes.returncode==0:
    matches=[]
    for line in processes.stdout.splitlines():
        parts=line.strip().split(None,1)
        if len(parts)!=2:continue
        pid,path=parts
        if pathlib.Path(path).name not in {'Simulator','SimulatorTrampoline'}:continue
        matches.append((pid,path))
    print(json.dumps(dict(observation='actual Simulator processes',processes=[dict(pid=pid,executable=path) for pid,path in matches])))
    for path in sorted({path for _,path in matches}):
        observe('actual executable code signature',['/usr/bin/codesign','-d','--verbose=2',path])
    if not any(pathlib.Path(path).name=='SimulatorTrampoline' for _,path in matches):
        print('No running SimulatorTrampoline was visible at this observation; its runtime identity remains unresolved.')
print('End read-only TCC observations. Native input/PCM and production acceptance guards remain required.')
PY
