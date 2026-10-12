import unittest,tempfile,pathlib,json
from decimal import Decimal
from context_budget import ContextBudgetDryRun,PER_ATTEMPT_USD,cost_envelope

class ContextBudgetTests(unittest.TestCase):
    def setUp(self):self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
    def create(self,name='context',budget='7.2192'):
        r=ContextBudgetDryRun(pathlib.Path(self.temp.name)/name,name,budget);self.addCleanup(r.close);return r
    def test_context_bound_includes_all_input_not_unmeasured_10000(self):
        self.assertEqual(PER_ATTEMPT_USD,Decimal('0.36096'))
        e=cost_envelope();self.assertEqual(Decimal(e['apiMaxUsd']),Decimal('7.2192'));self.assertEqual(Decimal(e['totalEnvelopeTwd']),Decimal('846.5216'));self.assertFalse(e['liveReady'])
    def test_failed_attempts_reserve_context_bound_and_never_refund(self):
        r=self.create()
        for i in range(20):r.attempt('same-retry',{'outcome':'timeout' if i%2 else 'error'})
        with self.assertRaises(RuntimeError):r.attempt('21',{})
        s=r.snapshot();self.assertEqual(s['attemptsUsed'],20);self.assertEqual(Decimal(s['reservedPlannedUsd']),Decimal('7.2192'));self.assertIsNone(s['actualCostUsd'])
    def test_budget_boundary_and_cap_including_other_cost_reserve(self):
        r=self.create(budget='0.36096');r.attempt('one',{})
        with self.assertRaises(RuntimeError):r.attempt('two',{})
        with self.assertRaises(ValueError):self.create('overspend','11')
    def test_new_envelope_does_not_change_frozen_images_or_repeats(self):
        base=pathlib.Path(__file__).resolve().parents[2]/'test/fixtures/prescription_images'
        m=json.loads((base/'manifest.json').read_text());self.assertEqual(m['hardRepeats'],['S03','S11','S12','S16'])
        self.assertEqual(len(m['cases']),16)
