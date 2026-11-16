#!/usr/bin/env python3
"""Host regressions for the release gate; no credentials or network needed."""
import copy,hashlib,importlib.util,io,json,os,pathlib,tempfile,unittest,zipfile
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('native_acceptance',pathlib.Path(__file__).with_name('require_native_acceptance.py'))
gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
REPO='owner/repo';SHA='a'*40;RUN=9001

class NativeAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.data={f'actions/runs/{RUN}':dict(id=RUN,path='.github/workflows/ios.yml',head_sha=SHA,event='push',
            status='completed',conclusion='success',head_commit={'message':'Verify release [ui-only]'})}
        self.data[f'commits/{SHA}']=dict(sha=SHA,commit={'message':'Verify release [ui-only]'})
        self.expected=['StudioTests/testCreate','VoiceTests/testCapture']
        self.scope=dict(schemaVersion=1,repository=REPO,sourceSHA=SHA,runID=str(RUN),runAttempt='1',status='completed',exitCode=0,subprocessExitCode=0,timedOut=False,receivedSignal=None,scope='ui-only',scopeStatus='full-functional-pass',functionalInventoryVerified=True,expectedFunctionalTests=self.expected.copy(),requiredTestOutcomes={identifier:'passed' for identifier in self.expected})
        checks=[]
        for index,name in enumerate(gate.REQUIRED_JOBS,101):
            checks.append(dict(id=index,name=name,head_sha=SHA,app={'slug':'github-actions'},status='completed',conclusion='success',
                details_url=f'https://github.com/{REPO}/actions/runs/{RUN}/job/{index}'))
            self.data[f'actions/jobs/{index}']=dict(run_id=RUN,name=name,head_sha=SHA,status='completed',conclusion='success',
                check_run_url=f'https://api.github.com/repos/{REPO}/check-runs/{index}')
        self.key=f'commits/{SHA}/check-runs?filter=latest&per_page=100'
        self.data[self.key]={'check_runs':checks}
    def verify(self):return gate.require_native_acceptance(REPO,SHA,lambda path:copy.deepcopy(self.data[path]),lambda run_id:copy.deepcopy(self.scope),self.expected)
    @property
    def verification_run(self):return self.data[f'actions/runs/{RUN}']
    def test_full_and_ui_only_pushes_pass(self):
        for message,expected in [('Release candidate','full'),('Release [UI-ONLY] [compact-capture]','ui-only')]:
            with self.subTest(message=message):
                self.verification_run['head_commit']['message']=message
                self.data[f'commits/{SHA}']['commit']['message']=message
                self.scope['scope']=expected
                proof=self.verify();self.assertEqual(len(proof),3);self.assertEqual({item['scope'] for item in proof},{expected})
    def test_focused_or_capture_only_pushes_fail(self):
        for flag in ['[integration-only]','[INTEGRATION-ONLY]','[ru-capture]','[ui-only] [ru-capture]','[device-only]','[input-diagnostic]','[INPUT-DIAGNOSTIC]','[ui-only] [input-diagnostic]']:
            with self.subTest(flag=flag):
                self.verification_run['head_commit']['message']='Checkpoint '+flag
                self.scope['scope']='input-diagnostic' if 'diagnostic' in flag.casefold() else 'integration-only'
                self.scope['scopeStatus']='focused-pass'
                self.scope['functionalInventoryVerified']=False
                with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_actual_verification_manual_run_is_full_even_on_a_focused_commit(self):
        self.verification_run['event']='workflow_dispatch';self.verification_run['head_commit']['message']='Checkpoint [integration-only] [ru-capture]'
        self.assertEqual({item['scope'] for item in self.verify()},{'manual-full'})
    def test_manual_distribution_caller_never_upgrades_focused_push(self):
        self.verification_run['head_commit']['message']='Checkpoint [integration-only]'
        self.scope['scope']='integration-only';self.scope['scopeStatus']='focused-pass';self.scope['functionalInventoryVerified']=False
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
                if kind=='missing-push-scope':self.verification_run.pop('head_commit');self.data[f'commits/{SHA}']['commit'].pop('message')
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
    def test_software_and_internal_beta_do_not_invent_physical_acceptance(self):
        for classification in ['software-verified','internal-beta']:
            with self.subTest(classification=classification):
                receipt=gate.classify_acceptance(REPO,SHA,'1.0.0','17',self.verify(),classification)
                self.assertTrue(receipt['softwareVerified'])
                self.assertFalse(receipt['physicalAccepted'])
                self.assertFalse(receipt['appReviewReady'])
                self.assertEqual(receipt['sourceSHA'],SHA)
                self.assertNotIn('physicalEvidence',receipt)
    def test_release_ready_requires_completed_matching_device_receipt(self):
        for document in [None,{},dict(schemaVersion=1,classification='release-ready',physicalAcceptance=False)]:
            with self.subTest(document=document):
                with self.assertRaises(gate.AcceptanceError):
                    gate.classify_acceptance(REPO,SHA,'1.0.0','17',self.verify(),'release-ready',document)
    def test_unknown_classification_fails_closed(self):
        with self.assertRaises(gate.AcceptanceError):
            gate.classify_acceptance(REPO,SHA,'1.0.0','17',self.verify(),'marketing-ready')
    def test_candidate_version_and_build_come_from_selected_source(self):
        version,build=gate.candidate_version()
        self.assertRegex(version,r'^\d+\.\d+\.\d+$')
        self.assertRegex(build,r'^\d+$')
    def test_release_ready_requires_hash_checked_files_and_keeps_source_identity(self):
        from test_device_acceptance import synthetic_document
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);document=synthetic_document(root)
            result=gate.classify_acceptance(REPO,SHA,'1.0.0','17',self.verify(),'release-ready',document,root)
            self.assertTrue(result['physicalAccepted']);self.assertTrue(result['appReviewReady'])
            self.assertEqual(result['physicalEvidence']['sourceSHA'],SHA)
            document['installedCandidates'][0]['build']='16'
            with self.assertRaises(gate.AcceptanceError):
                gate.classify_acceptance(REPO,SHA,'1.0.0','17',self.verify(),'release-ready',document,root)
    def test_classification_never_accepts_empty_or_mixed_software_proof(self):
        proof=self.verify();proof[1]['run_id']+=1
        for value in [[],proof]:
            with self.assertRaises(gate.AcceptanceError):
                gate.classify_acceptance(REPO,SHA,'1.0.0','17',value,'internal-beta')
    def test_associated_commit_flags_cannot_hide_behind_generic_run_message(self):
        for flag in ['[integration-only]','[INPUT-DIAGNOSTIC]','[ui-only] [ru-capture]']:
            with self.subTest(flag=flag):
                self.verification_run['head_commit']['message']='Generic workflow display title'
                self.data[f'commits/{SHA}']['commit']['message']='Actual source '+flag
                self.scope['scope']='integration-only';self.scope['scopeStatus']='focused-pass';self.scope['functionalInventoryVerified']=False
                with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_actual_complete_inventory_can_prove_full_rerun_on_focused_commit(self):
        self.verification_run['head_commit']['message']='Checkpoint [integration-only]'
        self.data[f'commits/{SHA}']['commit']['message']='Checkpoint [input-diagnostic]'
        self.scope['scope']='full'
        self.assertEqual({item['scopeStatus'] for item in self.verify()},{'full-functional-pass'})
    def test_three_green_jobs_with_zero_tests_missing_or_old_attempt_receipt_fail(self):
        baseline=copy.deepcopy(self.scope)
        for value in [None,{},dict(baseline,requiredTestOutcomes={}),dict(baseline,expectedFunctionalTests=[]),dict(baseline,runAttempt='0'),dict(baseline,subprocessExitCode=65)]:
            with self.subTest(value=value):
                self.scope=value
                with self.assertRaises(gate.AcceptanceError):self.verify()
    def test_classification_requires_actual_inventory_proof_not_only_job_names(self):
        proof=self.verify()
        for item in proof:item.pop('scopeStatus')
        with self.assertRaises(gate.AcceptanceError):
            gate.classify_acceptance(REPO,SHA,'1.0.0','17',proof,'internal-beta')
    def artifact_fixture(self,filename='native-process-status.json'):
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as archive:archive.writestr(filename,json.dumps(self.scope))
        payload=stream.getvalue()
        metadata=dict(id=123,name='native-acceptance-scope',expired=False,size_in_bytes=len(payload),digest='sha256:'+hashlib.sha256(payload).hexdigest(),workflow_run=dict(id=RUN,head_sha=SHA))
        return payload,metadata
    def test_scope_artifact_is_downloaded_by_verified_origin_size_and_digest(self):
        payload,metadata=self.artifact_fixture()
        receipt=gate.read_native_scope_artifact(REPO,SHA,RUN,lambda path:{'artifacts':[metadata]},lambda path,limit:payload)
        self.assertEqual(receipt,self.scope)
    def test_missing_expired_wrong_source_or_changed_scope_artifact_fails(self):
        payload,metadata=self.artifact_fixture()
        cases=[[],[dict(metadata,expired=True)],[dict(metadata,workflow_run=dict(id=RUN,head_sha='b'*40))],[dict(metadata,digest='sha256:'+'0'*64)],[dict(metadata,size_in_bytes=len(payload)+1)]]
        for artifacts in cases:
            with self.subTest(artifacts=artifacts):
                with self.assertRaises(gate.AcceptanceError):
                    gate.read_native_scope_artifact(REPO,SHA,RUN,lambda path:{'artifacts':artifacts},lambda path,limit:payload)
    def test_scope_artifact_wrong_layout_cannot_supply_unrelated_json(self):
        payload,metadata=self.artifact_fixture('another-status.json')
        with self.assertRaises(gate.AcceptanceError):
            gate.read_native_scope_artifact(REPO,SHA,RUN,lambda path:{'artifacts':[metadata]},lambda path,limit:payload)

if __name__=='__main__':unittest.main()
