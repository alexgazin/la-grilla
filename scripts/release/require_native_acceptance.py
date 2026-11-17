#!/usr/bin/env python3
"""Require coherent, complete functional acceptance for the exact release source."""
import argparse,hashlib,io,json,os,pathlib,re,sys,urllib.error,urllib.parse,urllib.request,zipfile
from device_acceptance import DeviceAcceptanceError,validate_device_acceptance

REQUIRED_JOBS=('ios','iphone','release-archive')
VERIFICATION_WORKFLOW='.github/workflows/ios.yml'
PARTIAL_FLAGS=('[integration-only]','[ru-capture]','[device-only]','[input-diagnostic]')
CLASSIFICATIONS=('software-verified','internal-beta','release-ready')
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/ci'))
from native_scope import functional_inventory,validate_scope_receipt

class AcceptanceError(RuntimeError):pass

def require(condition,message):
    if not condition:raise AcceptanceError(message)

def verification_scope(run,verified_scope=None,commit_message=None):
    require(run.get('path','').split('@',1)[0]==VERIFICATION_WORKFLOW,'Checks did not originate in the verification workflow.')
    event=run.get('event')
    # This is the originating verification event, not the distribution caller,
    # which is always workflow_dispatch and has an upload_testflight input.
    # ios.yml has no dispatch inputs; its test filters read push.head_commit.
    if event=='workflow_dispatch':return 'manual-full'
    require(event=='push','Unknown verification event; run the full verification workflow.')
    message=(run.get('head_commit') or {}).get('message')
    messages=[value.casefold() for value in (message,commit_message) if isinstance(value,str)]
    require(bool(messages),'Verification push scope could not be determined.')
    # A correlated full inventory can prove a deliberate full rerun on a
    # commit whose message still contains an old focused flag. Job names alone
    # or a focused/zero-test artifact can never override these flags.
    partial=any(flag in value for value in messages for flag in PARTIAL_FLAGS)
    require(not partial or verified_scope in ('full','ui-only'),'Focused or capture-only verification cannot authorize distribution without explicit full inventory evidence.')
    return verified_scope or ('ui-only' if any('[ui-only]' in value for value in messages) else 'full')

def require_native_acceptance(repo,sha,read_json,read_native_evidence=None,expected_tests=None):
    require(bool(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repo)),'Invalid repository identity.')
    require(bool(re.fullmatch(r'[0-9a-fA-F]{40}',sha)),'Invalid exact source identity.')
    checks=read_json(f'commits/{sha}/check-runs?filter=latest&per_page=100').get('check_runs',[])
    runs={};proof=[]
    for name in REQUIRED_JOBS:
        candidates=[item for item in checks if item.get('name')==name]
        require(bool(candidates),f'Missing {name} check for the exact source commit.')
        check=max(candidates,key=lambda item:item['id'])
        require(check.get('status')=='completed' and check.get('conclusion')=='success',f'{name} has not passed for this commit.')
        require(check.get('head_sha')==sha,f'{name} check belongs to another source.')
        require((check.get('app') or {}).get('slug')=='github-actions',f'{name} check is not from GitHub Actions.')
        link=urllib.parse.urlparse(check.get('details_url') or '')
        match=re.fullmatch('/'+re.escape(repo)+r'/actions/runs/(\d+)/job/(\d+)/?',link.path)
        require(link.scheme=='https' and link.netloc=='github.com' and match is not None,f'{name} has no verifiable workflow origin.')
        run_id,job_id=map(int,match.groups())
        if run_id not in runs:runs[run_id]=read_json(f'actions/runs/{run_id}')
        run=runs[run_id]
        require(run.get('id')==run_id and run.get('head_sha')==sha,f'{name} workflow belongs to another source.')
        require(run.get('status')=='completed' and run.get('conclusion')=='success',f'{name} workflow has not completed successfully.')
        require(run.get('path','').split('@',1)[0]==VERIFICATION_WORKFLOW,'Checks did not originate in the verification workflow.')
        job=read_json(f'actions/jobs/{job_id}')
        require(job.get('run_id')==run_id and job.get('head_sha')==sha and job.get('name')==name,f'{name} job provenance does not match.')
        require(job.get('check_run_url')==f'https://api.github.com/repos/{repo}/check-runs/{check["id"]}',f'{name} job does not match its selected check.')
        require(job.get('status')=='completed' and job.get('conclusion')=='success',f'{name} job has not passed.')
        job_attempt=job.get('run_attempt',run.get('run_attempt',1))
        require(type(job_attempt) is int and job_attempt>0,f'{name} job attempt could not be verified.')
        proof.append(dict(name=name,run_id=run_id,job_id=job_id,job_attempt=job_attempt))
    require(len(runs)==1,'Acceptance jobs came from different workflow runs; verify one coherent run.')
    run_id=next(iter(runs));run=runs[run_id]
    commit=read_json(f'commits/{sha}')
    require(commit.get('sha')==sha and isinstance((commit.get('commit') or {}).get('message'),str),'Associated commit identity/scope could not be verified.')
    require(read_native_evidence is not None,'Native scope and actual functional test inventory evidence is required.')
    try:
        inventory=expected_tests if expected_tests is not None else functional_inventory(ROOT/'UITests')
        # A retried SDK/archive job advances the workflow's latest attempt but
        # does not rerun a successful ios job. Correlate native evidence with
        # that selected job's actual attempt, not the unrelated latest retry.
        native_attempt=next(item['job_attempt'] for item in proof if item['name']=='ios')
        evidence=validate_scope_receipt(read_native_evidence(run_id),repo,sha,run_id,native_attempt,inventory)
    except ValueError as error:raise AcceptanceError(str(error)) from None
    scope=verification_scope(run,evidence['scope'],commit['commit']['message'])
    for item in proof:item.update(scope=scope,scopeStatus=evidence['scopeStatus'],functionalTestCount=evidence['functionalTestCount'])
    return proof

def read_native_scope_artifact(repo,sha,run_id,read_json,download):
    artifacts=read_json(f'actions/runs/{run_id}/artifacts?per_page=100').get('artifacts',[])
    candidates=[item for item in artifacts if item.get('name')=='native-acceptance-scope' and item.get('expired') is False]
    require(bool(candidates),'Missing unexpired native scope artifact; run full verification for this exact source.')
    artifact=max(candidates,key=lambda item:item['id'])
    require(type(artifact.get('size_in_bytes')) is int and 0<artifact['size_in_bytes']<=2_000_000,'Native scope artifact size is invalid.')
    origin=artifact.get('workflow_run') or {}
    require(origin.get('id')==run_id and origin.get('head_sha')==sha,'Native scope artifact belongs to another source/run.')
    payload=download(f'actions/artifacts/{artifact["id"]}/zip',2_000_000)
    require(len(payload)==artifact['size_in_bytes'],'Native scope artifact is incomplete.')
    digest=artifact.get('digest')
    if digest is not None:
        require(digest=='sha256:'+hashlib.sha256(payload).hexdigest(),'Native scope artifact digest does not match.')
    try:
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            files=[entry for entry in archive.infolist() if not entry.is_dir()]
            require(len(files)==1 and files[0].filename=='native-process-status.json' and files[0].file_size<=2_000_000,'Native scope artifact has an unexpected receipt layout.')
            return json.loads(archive.read(files[0]))
    except (ValueError,zipfile.BadZipFile,KeyError):raise AcceptanceError('Native scope artifact is not a readable status receipt.') from None

def classify_acceptance(repo,sha,version,build,proof,classification,device_receipt=None,evidence_root=ROOT):
    require(classification in CLASSIFICATIONS,'Unknown acceptance classification.')
    require(isinstance(proof,list) and len(proof)==len(REQUIRED_JOBS) and
            all(isinstance(item,dict) for item in proof) and
            {item.get('name') for item in proof}==set(REQUIRED_JOBS) and
            len({item.get('run_id') for item in proof})==1 and
            all(type(item.get('run_id')) is int and item['run_id']>0 and type(item.get('job_id')) is int and item['job_id']>0 and
                item.get('scopeStatus')=='full-functional-pass' and type(item.get('functionalTestCount')) is int and item['functionalTestCount']>0 for item in proof),
            'A classification requires one coherent verified UI/SDK/archive proof.')
    result=dict(schemaVersion=1,repository=repo,sourceSHA=sha,version=version,build=str(build),
                classification=classification,softwareVerified=True,physicalAccepted=False,
                appReviewReady=False,verificationJobs=proof)
    if classification=='release-ready':
        require(device_receipt is not None,'Release-ready classification requires a completed physical evidence receipt.')
        try:
            result['physicalEvidence']=validate_device_acceptance(device_receipt,repo,sha,version,str(build),evidence_root)
        except DeviceAcceptanceError as error:raise AcceptanceError(str(error)) from None
        result.update(physicalAccepted=True,appReviewReady=True)
    return result

def candidate_version(root=ROOT):
    project=(root/'project.yml').read_text()
    version=re.findall(r"^\s*MARKETING_VERSION: '([^']+)'\s*$",project,re.M)
    build=re.findall(r"^\s*CURRENT_PROJECT_VERSION: '(\d+)'\s*$",project,re.M)
    require(len(version)==1 and len(build)==1,'Could not identify this candidate version/build unambiguously.')
    return version[0],build[0]

def main(argv=()):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classification',choices=CLASSIFICATIONS,default=os.environ.get('GRILLA_ACCEPTANCE_CLASSIFICATION') or 'software-verified')
    parser.add_argument('--device-receipt',default=os.environ.get('GRILLA_DEVICE_RECEIPT'))
    parser.add_argument('--output',type=pathlib.Path,default=pathlib.Path('ReleaseArtifacts/native-acceptance.json'))
    arguments=parser.parse_args(argv)
    repo=os.environ['GITHUB_REPOSITORY'];sha=os.environ['GITHUB_SHA'];token=os.environ['GH_TOKEN']
    def read_json(path):
        request=urllib.request.Request(f'https://api.github.com/repos/{repo}/{path}',headers={
            'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'})
        with urllib.request.urlopen(request,timeout=30) as response:return json.load(response)
    def download(path,limit):
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self,*_args,**_kwargs):return None
        request=urllib.request.Request(f'https://api.github.com/repos/{repo}/{path}',headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'})
        try:
            with urllib.request.build_opener(NoRedirect).open(request,timeout=30) as response:data=response.read(limit+1)
        except urllib.error.HTTPError as error:
            require(error.code in (301,302,303,307,308),'Native scope artifact download failed.')
            location=error.headers.get('Location','');target=urllib.parse.urlparse(location)
            require(target.scheme=='https' and target.hostname and target.username is None and target.password is None,'Native scope artifact redirect is invalid.')
            # Never forward the GitHub bearer token to the artifact storage host.
            with urllib.request.urlopen(urllib.request.Request(location),timeout=30) as response:data=response.read(limit+1)
        require(len(data)<=limit,'Native scope artifact exceeds its download limit.')
        return data
    try:
        proof=require_native_acceptance(repo,sha,read_json,lambda run_id:read_native_scope_artifact(repo,sha,run_id,read_json,download))
        version,build=candidate_version()
        device_receipt=None
        if arguments.classification=='release-ready':
            require(bool(arguments.device_receipt),'Release-ready classification requires a completed physical evidence receipt.')
            receipt_path=(ROOT/arguments.device_receipt).resolve()
            require(receipt_path.is_relative_to(ROOT) and receipt_path.suffix=='.json','Physical receipt must be a JSON file inside this source checkout.')
            require(receipt_path.is_file() and receipt_path.stat().st_size<=2_000_000,'Physical receipt is missing or exceeds its size limit.')
            device_receipt=json.loads(receipt_path.read_text())
        result=classify_acceptance(repo,sha,version,build,proof,arguments.classification,device_receipt)
        if device_receipt is not None:result['deviceReceiptPath']=receipt_path.relative_to(ROOT).as_posix()
        arguments.output.parent.mkdir(parents=True,exist_ok=True)
        arguments.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    except AcceptanceError as error:raise SystemExit(str(error))
    except Exception as error:
        # Do not print request URLs, headers, tokens or server response bodies.
        raise SystemExit('Could not verify native acceptance ('+type(error).__name__+').')
    print('Exact source passed coherent native UI/SDK/archive acceptance ('+proof[0]['scope']+'); classification: '+arguments.classification+'.')
    if arguments.classification!='release-ready':
        print('Physical acceptance is not claimed; this receipt does not classify the app as App Review ready.')

if __name__=='__main__':main(sys.argv[1:])
