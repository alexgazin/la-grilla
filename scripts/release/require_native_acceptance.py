#!/usr/bin/env python3
import os,json,urllib.request
repo=os.environ['GITHUB_REPOSITORY'];sha=os.environ['GITHUB_SHA']
request=urllib.request.Request(f'https://api.github.com/repos/{repo}/commits/{sha}/check-runs?per_page=100',headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'Accept':'application/vnd.github+json'})
with urllib.request.urlopen(request,timeout=30) as response:runs=json.load(response)['check_runs']
for name in ['ios','iphone','release-archive']:
 candidates=[r for r in runs if r['name']==name];assert candidates,f'Missing {name} check for the exact source commit'
 latest=max(candidates,key=lambda r:r['id']);assert latest['status']=='completed' and latest['conclusion']=='success',f'{name} has not passed for this commit'
print('Exact source commit passed native UI/SDK and Release archive checks.')
