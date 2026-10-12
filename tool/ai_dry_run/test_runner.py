import ast, decimal, hashlib, json, pathlib, tempfile, unittest, sqlite3, threading
from runner import DryRun, PER_ATTEMPT, units
ROOT=pathlib.Path(__file__).resolve().parents[2]

class RunnerTests(unittest.TestCase):
    def setUp(self):self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
    def run_new(self,name='a',budget='1.37445'):
        r=DryRun(pathlib.Path(self.temp.name)/name,name,budget);self.addCleanup(r.close);return r
    def test_cost_arithmetic_is_conditional_not_real_usage(self):
        bound=(decimal.Decimal(10000+1105)*decimal.Decimal('2.5')+4096*decimal.Decimal(10))/1000000
        self.assertEqual(bound,PER_ATTEMPT);self.assertEqual(bound*20,decimal.Decimal('1.37445'))
        s=self.run_new().snapshot();self.assertFalse(s['billingVerified']);self.assertIsNone(s['actualCostUsd'])
    def test_attempt_cap_includes_failures_warmup_and_retries(self):
        r=self.run_new()
        for i in range(20):r.attempt('warmup' if i==0 else 'same-logical',{'outcome':['timeout','rate_limit','error','success'][i%4]})
        with self.assertRaises(RuntimeError):r.attempt('extra',{})
        s=r.snapshot();self.assertEqual(s['attemptsUsed'],20);self.assertEqual(s['logicalSamplesUsed'],2);self.assertEqual(s['reservedPlannedUsd'],'1.3744500');self.assertEqual(s['state'],'stopped')
    def test_exact_budget_boundary_and_no_refund(self):
        r=self.run_new(budget=str(PER_ATTEMPT));r.attempt('x',{'outcome':'timeout'})
        with self.assertRaises(RuntimeError):r.attempt('retry',{})
        self.assertEqual(r.snapshot()['attemptsUsed'],1)
        small=self.run_new('small','0.0687224')
        with self.assertRaises(RuntimeError):small.attempt('x',{})
        self.assertEqual(small.snapshot()['attemptsUsed'],0)
    def test_reservation_durable_before_any_simulation_or_crash(self):
        r=self.run_new();r.reserve('interrupted')
        self.assertEqual(r.snapshot()['attempts'][0]['outcome'],'reserved')
        self.assertEqual(r.snapshot()['attempts'][0]['reservedPlannedUsd'],'0.0687225')
        self.assertIsNone(r.snapshot()['attempts'][0]['rawResponse'])
    def test_atomic_reservation_across_independent_connections(self):
        r=self.run_new(budget=str(PER_ATTEMPT*2));barrier=threading.Barrier(6);failures=[]
        def reserve():
            other=object.__new__(DryRun);other.path=r.path;other.db=sqlite3.connect(r.path/'journal.sqlite',timeout=5)
            try:
                barrier.wait()
                try:other.reserve('concurrent')
                except RuntimeError:pass
            except Exception as e:failures.append(e)
            finally:other.close()
        threads=[threading.Thread(target=reserve) for _ in range(6)]
        for t in threads:t.start()
        for t in threads:t.join()
        self.assertEqual(failures,[]);self.assertEqual(r.snapshot()['attemptsUsed'],2)
        self.assertEqual(decimal.Decimal(r.snapshot()['reservedPlannedUsd']),PER_ATTEMPT*2)
    def test_stop_cannot_continue_or_reopen_existing_run(self):
        r=self.run_new();r.stop()
        with self.assertRaises(RuntimeError):r.attempt('late',{})
        with self.assertRaises(FileExistsError):DryRun(r.path,'new-label')
        new=self.run_new('explicit-new-run');new.attempt('x',{});self.assertEqual(new.snapshot()['attemptsUsed'],1)
    def test_stop_between_reservation_and_simulation_consumes_without_execute(self):
        r=self.run_new();reserve=r.reserve
        def stopped(logical):
            i=reserve(logical);r.stop();return i
        r.reserve=stopped
        class NotRead(dict):
            def get(self,*args):raise AssertionError('fixture must not execute after stop')
        r.attempt('x',NotRead());self.assertEqual(r.snapshot()['attempts'][0]['outcome'],'stopped_before_simulation')
    def test_export_cannot_overwrite_existing_snapshot(self):
        r=self.run_new();r.attempt('x',{});path=r.export();before=path.read_bytes()
        with self.assertRaises(FileExistsError):r.export()
        self.assertEqual(path.read_bytes(),before)
    def test_completed_run_cannot_resume(self):
        r=self.run_new();r.finish()
        with self.assertRaises(RuntimeError):r.attempt('x',{})
    def test_virtual_sequential_clock_rate_limit_no_sleep(self):
        r=self.run_new()
        for i in range(20):r.attempt(str(i),{'simulatedLatencyMs':150 if i%2 else 15000})
        rows=r.snapshot()['attempts'];starts=[x['virtualStartMs'] for x in rows]
        self.assertTrue(all(b-a>=12000 for a,b in zip(starts,starts[1:])))
        for t in starts:self.assertLessEqual(sum(t<=x<t+60000 for x in starts),5)
    def test_raw_envelope_and_missing_usage_preserved_without_claims(self):
        r=self.run_new();raw='not JSON\nSYNTH only'
        r.attempt('a',{'rawResponse':raw,'finish_reason':'length','simulatedLatencyMs':33})
        r.attempt('a-retry',{'rawResponse':'{}','model':'synthetic-model','usage':{'total_tokens':12},'outcome':'error'})
        s=json.loads(r.export().read_text());self.assertEqual(s['attempts'][0]['rawResponse'],raw);self.assertEqual(s['attempts'][0]['finish_reason'],'length');self.assertIsNone(s['attempts'][0]['model']);self.assertIsNone(s['attempts'][0]['usage']);self.assertEqual(s['attempts'][1]['usageKind'],'fixture_not_measured');self.assertFalse(s['liveAuthorized'])
    def test_invalid_budget_and_case_inputs(self):
        for value in ['-1','NaN','0.00000001']:
            with self.assertRaises(ValueError):units(value)
        r=self.run_new()
        with self.assertRaises(ValueError):r.attempt('',{})
    def test_runner_has_no_network_secret_or_sleep_imports(self):
        tree=ast.parse((ROOT/'tool/ai_dry_run/runner.py').read_text())
        names={n.name for x in ast.walk(tree) if isinstance(x,ast.Import) for n in x.names}
        self.assertEqual(names,{'argparse','decimal','json','pathlib','sqlite3'})
        calls={x.func.attr for x in ast.walk(tree) if isinstance(x,ast.Call) and isinstance(x.func,ast.Attribute)}
        self.assertNotIn('sleep',calls);self.assertNotIn('getenv',calls)
    def test_image_manifest_and_source_contract_layers(self):
        base=ROOT/'test/fixtures/prescription_images';m=json.loads((base/'manifest.json').read_text());qa=json.loads((base/'visual_qa.json').read_text())
        self.assertEqual(len(m['cases']),16);self.assertEqual(m['hardRepeats'],['S03','S11','S12','S16'])
        self.assertEqual(hashlib.sha256((ROOT/'test/fixtures/prescription_eval/golden.json').read_bytes()).hexdigest(),m['sourceGoldenSha256'])
        for c in m['cases']:
            blob=(base/c['image']).read_bytes();self.assertEqual(hashlib.sha256(blob).hexdigest(),c['sha256']);self.assertEqual(qa['imageSha256'][c['caseId']],c['sha256']);self.assertEqual(len(blob),c['bytes']);self.assertLessEqual(len(blob),1048576);self.assertEqual((c['width'],c['height']),(1024,1536));self.assertEqual(int.from_bytes(blob[16:20],'big'),1024);self.assertEqual(int.from_bytes(blob[20:24],'big'),1536)
        english=m['cases'][2];self.assertIsNone(english['sourceImageTruth']['medicines'][0]['name']);self.assertEqual(english['expectedOutputContract']['fieldTruth']['medicines'][0]['name'],'SYNTH-03')
        self.assertEqual(m['cases'][10]['visibility']['medicines.0.dosage']['state'],'geometric_occlusion')
if __name__=='__main__':unittest.main()
