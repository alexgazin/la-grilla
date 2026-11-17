#!/usr/bin/env python3
"""Manual Linux snapshot repro, not an Apple SDK/native acceptance or CI gate.
Extracts the current helper and methods from --repo/App/Session.swift, and the
actual pre-fix edit method from a pinned local Git object. Uses real already
built MusicDomain objects and the unmodified static Swift runtime. Build paths,
compiler and output must be supplied for the current workspace. Outputs include
large binaries: use /tmp, never this documentation directory. Legacy abort is an
intentional child-only negative control; no network or source mutation occurs.
"""
from pathlib import Path
import argparse,subprocess,hashlib,json,signal,time,sys
p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,required=True);p.add_argument('--build',type=Path,required=True);p.add_argument('--swiftc',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--legacy-source',default='c5ee17c69b52341a47c1c0de76657b397054f604');a=p.parse_args();a.out.mkdir(exist_ok=True,parents=True)
current=(a.repo/'App/Session.swift').read_text();legacy_sha=a.legacy_source;legacy=subprocess.check_output(['git','show',legacy_sha+':App/Session.swift'],cwd=a.repo,text=True)
def extract(source,name):
 import re
 m=re.search(r'(?m)^    (?:private )?func '+name+r'(?:<[^>]+>)?\(',source);assert m,name
 start=m.start();opening=source.index('{',m.end());depth=0;quoted=False;escaped=False
 for i in range(opening,len(source)):
  c=source[i]
  if quoted:
   if escaped:escaped=False
   elif c=='\\':escaped=True
   elif c=='"':quoted=False
  else:
   if c=='"':quoted=True
   elif c=='{':depth+=1
   elif c=='}':
    depth-=1
    if depth==0:return source[start:i+1]
 raise ValueError(name)
names=['withHistoryTransaction','edit','mixerEdit','coalescedMusicEdit','undo','redo'];functions={n:extract(current,n) for n in names};old_edit=extract(legacy,'edit');assert 'history.apply(&project,change)' in old_edit
prefix='''import Foundation
import Observation
import MusicDomain
@MainActor final class NoLivePerformance {
 var contextActive=false
 func editMix(_ change:(inout Project)throws->Void)throws {preconditionFailure("Live performance is outside this stopped-source harness")}
}
@MainActor @Observable final class Harness {
 var project=Project(name:"Observation",bars:1)
 var history=History()
 var mixerGesture=false
 var recording=false
 var armed=false
 var message:String?
 let performance=NoLivePerformance()
 func sync(){}
 func scheduleSave(){}
 func restoreGeneratedLoop(){}
 func leavePerformance()async {preconditionFailure("Live performance is outside this stopped-source harness")}
'''
observe='''@MainActor final class Probe {var callbacks=0}
@MainActor func observe(_ state:Harness)->Probe {
 let probe=Probe()
 withObservationTracking {_ = state.project} onChange: {
  MainActor.assumeIsolated {probe.callbacks+=1;_ = state.history.canUndo}
 }
 return probe
}
'''
newmain='''@main struct Main {
 @MainActor static func main()throws {
  let state=Harness()
  var probe=observe(state)
  state.edit {$0.name="One"}
  precondition(probe.callbacks==1 && state.project.name=="One" && state.history.canUndo)
  probe=observe(state);state.undo()
  precondition(probe.callbacks==1 && state.project.name=="Observation" && state.history.canRedo)
  probe=observe(state);state.redo()
  precondition(probe.callbacks==1 && state.project.name=="One")
  state.mixerGesture=false
  probe=observe(state);state.mixerEdit {$0.master = -9}
  precondition(probe.callbacks==1 && state.project.master == -9)
  probe=observe(state);state.mixerEdit {$0.master = -12}
  precondition(probe.callbacks==1 && state.project.master == -12)
  probe=observe(state);state.undo()
  precondition(probe.callbacks==1 && state.project.master == -3, "Coalesced mix must undo as one gesture")
  state.mixerGesture=false
  probe=observe(state);state.coalescedMusicEdit {$0.name="Phrase A"}
  precondition(probe.callbacks==1 && state.project.name=="Phrase A")
  probe=observe(state);state.coalescedMusicEdit {$0.name="Phrase B"}
  precondition(probe.callbacks==1 && state.project.name=="Phrase B")
  probe=observe(state);state.undo()
  precondition(probe.callbacks==1 && state.project.name=="One", "Coalesced music must undo as one gesture")
  let before=state.project, canUndo=state.history.canUndo, canRedo=state.history.canRedo
  probe=observe(state);state.edit {$0.bpm = .nan}
  precondition(probe.callbacks==0 && state.project==before && state.history.canUndo==canUndo && state.history.canRedo==canRedo && state.message != nil)
  let empty=Harness();probe=observe(empty);empty.edit {$0.bpm = .nan}
  precondition(probe.callbacks==0 && empty.project.name=="Observation" && !empty.history.canUndo && !empty.history.canRedo)
  print("PASS extracted edit/undo/redo/mix/coalesced reentrancy, one-gesture Undo, throw rollback")
 }
}
'''
legacy_main='''@main struct Main {@MainActor static func main(){let state=Harness();let probe=observe(state);state.edit {$0.name="Legacy"};print("Unexpected legacy survival",probe.callbacks)}}'''
paths=[]
for name,text in [('current',prefix+'\n'.join(functions.values())+'\n}\n'+observe+newmain),('legacy',prefix+old_edit+'\n}\n'+observe+legacy_main)]:
 f=a.out/(name+'.swift');f.write_text(text);paths.append(f)
modules=list(a.build.glob('*/debug/Modules/MusicDomain.swiftmodule'));assert modules, a.build
module=modules[0].parent;build=module.parent;objects=sorted((build/'MusicDomain.build').glob('*.o'))+sorted((build/'AudioDSP.build').rglob('*.o'));assert objects
results={}
for f in paths:
 command=[str(a.swiftc),'-swift-version','6','-parse-as-library','-static-stdlib','-module-cache-path',str(a.out/'module-cache'),'-I',str(module),'-I',str(build/'AudioDSP.build'),str(f),*map(str,objects),'-lstdc++','-o',str(f.with_suffix(''))]
 compile=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(a.out/(f.stem+'-compile.log')).write_text(compile.stdout)
 if compile.returncode:print(compile.stdout);raise SystemExit(compile.returncode)
 result=subprocess.run([str(f.with_suffix(''))],cwd=a.out,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 (a.out/(f.stem+'-stdout.log')).write_text(result.stdout);(a.out/(f.stem+'-stderr.log')).write_text(result.stderr)
 results[f.stem]=dict(exitCode=result.returncode,stdout=result.stdout,stderrPrefix=result.stderr[:300])
print(json.dumps(results,indent=2))
assert results['legacy']['exitCode']==-signal.SIGABRT,results
assert 'Simultaneous accesses' in results['legacy']['stderrPrefix'],results
assert results['current']['exitCode']==0,results
report=dict(scope='Linux host Observation reentrancy regression with source-extracted Session methods and real MusicDomain; not Apple SDK or native UI acceptance',sourceSHA256=hashlib.sha256(current.encode()).hexdigest(),legacySourceSHA=legacy_sha,extractedFunctionSHA256={n:hashlib.sha256(v.encode()).hexdigest() for n,v in functions.items()},legacyFunctionSHA256=hashlib.sha256(old_edit.encode()).hexdigest(),results=results,status='passed',audioAndLivePerformance='Not exercised; stub branches precondition-fail if reached')
(a.out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
