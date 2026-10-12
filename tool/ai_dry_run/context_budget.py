"""Reviewed cost-envelope dry-run only; no auth or network capability."""
from decimal import Decimal
from runner import DryRun, units, MAX_ATTEMPTS, INTERVAL_MS

CONTEXT_INPUT = 128000
MAX_OUTPUT = 4096
INPUT_PRICE = Decimal('2.50')
OUTPUT_PRICE = Decimal('10')
PER_ATTEMPT_USD = (CONTEXT_INPUT * INPUT_PRICE + MAX_OUTPUT * OUTPUT_PRICE) / 1000000
FX_RESERVE = Decimal('40')
FEE_MULTIPLIER = Decimal('1.2') # Envelope threshold, not actual tax/FX evidence.
CLOUD_RESERVE_TWD = Decimal('200')
SAFETY_TWD = Decimal('300')
TOTAL_CAP_TWD = Decimal('1000')

def cost_envelope():
    api = MAX_ATTEMPTS * PER_ATTEMPT_USD * FX_RESERVE * FEE_MULTIPLIER
    return {'perAttemptUsd':str(PER_ATTEMPT_USD),'maxAttempts':MAX_ATTEMPTS,
      'apiMaxUsd':str(PER_ATTEMPT_USD*MAX_ATTEMPTS),'apiEnvelopeTwd':str(api),
      'cloudReserveTwd':str(CLOUD_RESERVE_TWD),'safetyTwd':str(SAFETY_TWD),
      'totalEnvelopeTwd':str(api+CLOUD_RESERVE_TWD+SAFETY_TWD),
      'unallocatedTwd':str(TOTAL_CAP_TWD-api-CLOUD_RESERVE_TWD-SAFETY_TWD),
      'conditions':['fixed gpt-4o standard tariff/context unchanged','max_tokens<=4096; image/input counted within context','actual FX and all fee/tax multipliers <= reserve thresholds','deployment/storage/cloud within NT200, finite horizon','no extra/background/implicit retries; app session not wired'],
      'liveReady':False,'actualCostTwd':None}

class ContextBudgetDryRun(DryRun):
    def __init__(self, directory, run_id, budget='7.2192'):
        if Decimal(budget)*FX_RESERVE*FEE_MULTIPLIER+CLOUD_RESERVE_TWD+SAFETY_TWD > TOTAL_CAP_TWD:
            raise ValueError('Budget exceeds NT1000 envelope')
        super().__init__(directory,run_id,budget)
    def reserve(self, logical_id):
        if not isinstance(logical_id,str) or not logical_id: raise ValueError('Logical ID required')
        self.db.execute('BEGIN IMMEDIATE')
        try:
            state,budget,clock=self.db.execute('SELECT state,budget,clock FROM run').fetchone()
            if state!='running':raise RuntimeError('Stopped/complete run cannot continue')
            count,total,last=self.db.execute('SELECT count(*),coalesce(sum(reserved),0),max(start_ms) FROM attempts').fetchone()
            if count>=MAX_ATTEMPTS or total+units(PER_ATTEMPT_USD)>budget:
                self.db.execute("UPDATE run SET state='stopped'");self.db.commit()
                raise RuntimeError('Context-budget/attempt cap reached')
            start=max(clock,0 if last is None else last+INTERVAL_MS)
            row=self.db.execute('INSERT INTO attempts(logical_id,reserved,start_ms,outcome) VALUES (?,?,?,?)',(logical_id,units(PER_ATTEMPT_USD),start,'reserved'))
            self.db.execute('UPDATE run SET clock=?',(start,));self.db.commit();return row.lastrowid
        except Exception:
            if self.db.in_transaction:self.db.rollback()
            raise
    def snapshot(self):
        data=super().snapshot()
        data['reservationKind']='documented_context_envelope_dry_run_not_live_billing'
        data['reservationAssumptions']={'inputContextTokens':CONTEXT_INPUT,'maxOutputTokens':MAX_OUTPUT,'inputUsdPerMillion':str(INPUT_PRICE),'outputUsdPerMillion':str(OUTPUT_PRICE),'fxReserve':str(FX_RESERVE),'feeMultiplierThreshold':str(FEE_MULTIPLIER)}
        data['costEnvelope']=cost_envelope()
        return data
