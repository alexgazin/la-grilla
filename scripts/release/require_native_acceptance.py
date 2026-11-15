#!/usr/bin/env python3
"""Require coherent, complete functional acceptance for the exact release source."""
import json,os,re,sys,urllib.parse,urllib.request

REQUIRED_JOBS=('ios','iphone','release-archive')
VERIFICATION_WORKFLOW='.github/workflows/ios.yml'
PARTIAL_FLAGS=('[integration-only]','[ru-capture]','[device-only]')

class AcceptanceError(RuntimeError):pass

def require(condition,message):
    if not condition:raise AcceptanceError(message)

def verification_scope(run):
    require(run.get('path','').split('@',1)[0]==VERIFICATION_WORKFLOW,'Checks did not originate in the verification workflow.')
    event=run.get('event')
    # This is the originating verification event, not the distribution caller,
    # which is always workflow_dispatch and has an upload_testflight input.
    # ios.yml has no dispatch inputs; its test filters read push.head_commit.
    if event=='workflow_dispatch':return 'manual-full'
    require(event=='push','Unknown verification event; run the full verification workflow.')
    message=(run.get('head_commit') or {}).get('message')
    require(isinstance(message,str),'Verification push scope could not be determined.')
    message=message.casefold() # Actions contains() is case-insensitive too.
    require(not any(flag in message for flag in PARTIAL_FLAGS),'Focused or capture-only verification cannot authorize distribution.')
    return 'ui-only' if '[ui-only]' in message else 'full'

def require_native_acceptance(repo,sha,read_json):
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
        scope=verification_scope(run)
        job=read_json(f'actions/jobs/{job_id}')
        require(job.get('run_id')==run_id and job.get('head_sha')==sha and job.get('name')==name,f'{name} job provenance does not match.')
        require(job.get('check_run_url')==f'https://api.github.com/repos/{repo}/check-runs/{check["id"]}',f'{name} job does not match its selected check.')
        require(job.get('status')=='completed' and job.get('conclusion')=='success',f'{name} job has not passed.')
        proof.append(dict(name=name,run_id=run_id,job_id=job_id,scope=scope))
    require(len(runs)==1,'Acceptance jobs came from different workflow runs; verify one coherent run.')
    return proof

def main():
    repo=os.environ['GITHUB_REPOSITORY'];sha=os.environ['GITHUB_SHA'];token=os.environ['GH_TOKEN']
    def read_json(path):
        request=urllib.request.Request(f'https://api.github.com/repos/{repo}/{path}',headers={
            'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'})
        with urllib.request.urlopen(request,timeout=30) as response:return json.load(response)
    try:
        proof=require_native_acceptance(repo,sha,read_json)
    except AcceptanceError as error:raise SystemExit(str(error))
    except Exception as error:
        # Do not print request URLs, headers, tokens or server response bodies.
        raise SystemExit('Could not verify native acceptance ('+type(error).__name__+').')
    print('Exact source passed coherent native UI/SDK/archive acceptance ('+proof[0]['scope']+').')

if __name__=='__main__':main()
