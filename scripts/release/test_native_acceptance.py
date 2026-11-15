#!/usr/bin/env python3
"""Host regressions for the release gate; no credentials or network needed."""
import copy,importlib.util,os,pathlib,unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('native_acceptance',pathlib.Path(__file__).with_name('require_native_acceptance.py'))
gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
REPO='owner/repo';SHA='a'*40;RUN=9001

class NativeAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.data={f'actions/runs/{RUN}':dict(id=RUN,path='.github/workflows/ios.yml',head_sha=SHA,event='push',
            status='completed',conclusion='success',head_commit={'message':'Verify release [ui-only]'})}
        checks=[]
        for index,name in enumerate(gate.REQUIRED_JOBS,101):
            checks.append(dict(id=index,name=name,head_sha=SHA,app={'slug':'github-actions'},status='completed',conclusion='success',
                details_url=f'https://github.com/{REPO}/actions/runs/{RUN}/job/{index}'))
            self.data[f'actions/jobs/{index}']=dict(run_id=RUN,name=name,head_sha=SHA,status='completed',conclusion='success',
                check_run_url=f'https://api.github.com/repos/{REPO}/check-runs/{index}')
        self.key=f'commits/{SHA}/check-runs?filter=latest&per_page=100'
        self.data[self.key]={'check_runs':checks}
    def verify(self):return gate.require_native_acceptance(REPO,SHA,lambda path:copy.deepcopy(self.data[path]))
    @property
    def verification_run(self):return self.data[f'actions/runs/{RUN}']
    def test_full_and_ui_only_pushes_pass(self):
        for message,expected in [('Release candidate','full'),('Release [UI-ONLY] [compact-capture]','ui-only')]:
            with self.subTest(message=message):
                self.verification_run['head_commit']['message']=message
                proof=self.verify();self.assertEqual(len(proof),3);self.assertEqual({item['scope'] for item in proof},{expected})
    def test_focused_or_capture_only_pushes_fail(self):
        for flag in ['[integration-only]','[INTEGRATION-ONLY]','[ru-capture]','[ui-only] [ru-capture]','[device-only]','[input-diagnostic]','[INPUT-DIAGNOSTIC]','[ui-only] [input-diagnostic]']:
            with self.subTest(flag=flag):
                self.verification_run['head_commit']['message']='Checkpoint '+flag
                with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_actual_verification_manual_run_is_full_even_on_a_focused_commit(self):
        self.verification_run['event']='workflow_dispatch';self.verification_run['head_commit']['message']='Checkpoint [integration-only] [ru-capture]'
        self.assertEqual({item['scope'] for item in self.verify()},{'manual-full'})
    def test_manual_distribution_caller_never_upgrades_focused_push(self):
        self.verification_run['head_commit']['message']='Checkpoint [integration-only]'
        with patch.dict(os.environ,{'GITHUB_EVENT_NAME':'workflow_dispatch','INPUT_UPLOAD_TESTFLIGHT':'true'}):
            with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_manual_run_from_distribution_workflow_is_not_acceptance(self):
        self.verification_run.update(event='workflow_dispatch',path='.github/workflows/distribution.yml')
        with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_wrong_source_in_check_run_or_job_fails(self):
        baseline=copy.deepcopy(self.data)
        for kind in ['check','run','job']:
            with self.subTest(kind=kind):
                self.data=copy.deepcopy(baseline)
                target=self.data[self.key]['check_runs'][0] if kind=='check' else self.verification_run if kind=='run' else self.data['actions/jobs/101']
                target['head_sha']='b'*40
                with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_latest_failed_check_cannot_reuse_older_success(self):
        newer=copy.deepcopy(self.data[self.key]['check_runs'][0]);newer.update(id=999,conclusion='failure')
        self.data[self.key]['check_runs'].append(newer)
        with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_mixed_successful_runs_do_not_form_one_acceptance(self):
        other=copy.deepcopy(self.verification_run);other['id']=RUN+1;self.data[f'actions/runs/{RUN+1}']=other
        self.data[self.key]['check_runs'][1]['details_url']=f'https://github.com/{REPO}/actions/runs/{RUN+1}/job/102'
        self.data['actions/jobs/102']['run_id']=RUN+1
        with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_unfinished_workflow_or_mismatched_job_fails(self):
        self.verification_run['status']='in_progress'
        with self.assertRaises(gate.AcceptanceError):self.verify()
        self.verification_run['status']='completed';self.data['actions/jobs/101']['check_run_url']='https://api.github.com/repos/owner/repo/check-runs/999'
        with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_missing_scope_unknown_event_and_untrusted_check_fail(self):
        baseline=copy.deepcopy(self.data)
        for kind in ['missing-push-scope','unknown-event','other-app','missing-check']:
            with self.subTest(kind=kind):
                self.data=copy.deepcopy(baseline)
                if kind=='missing-push-scope':self.verification_run.pop('head_commit')
                elif kind=='unknown-event':self.verification_run['event']='workflow_run'
                elif kind=='other-app':self.data[self.key]['check_runs'][0]['app']['slug']='some-other-app'
                else:self.data[self.key]['check_runs'].pop()
                with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_error_does_not_echo_untrusted_origin_url(self):
        self.data[self.key]['check_runs'][0]['details_url']='https://untrusted.invalid/private?token=DO-NOT-PRINT'
        with self.assertRaises(gate.AcceptanceError) as error:self.verify()
        self.assertNotIn('DO-NOT-PRINT',str(error.exception));self.assertNotIn('https://',str(error.exception))
    def test_cli_query_error_does_not_echo_url_or_token(self):
        with patch.dict(os.environ,{'GITHUB_REPOSITORY':REPO,'GITHUB_SHA':SHA,'GH_TOKEN':'PRIVATE-TOKEN'}):
            with patch.object(gate.urllib.request,'urlopen',side_effect=RuntimeError('https://private.invalid/?token=PRIVATE-TOKEN')):
                with self.assertRaises(SystemExit) as error:gate.main()
        self.assertNotIn('PRIVATE-TOKEN',str(error.exception));self.assertNotIn('https://',str(error.exception))

if __name__=='__main__':unittest.main()
