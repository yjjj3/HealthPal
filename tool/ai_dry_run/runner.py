#!/usr/bin/env python3
"""Dry-run only. No HTTP library, credentials, endpoint or live mode exists."""
import argparse, decimal, json, pathlib, sqlite3

UNIT = decimal.Decimal('0.0000001') # Exact planned USD accounting; not real bill.
PER_ATTEMPT = decimal.Decimal('0.0687225')
MAX_ATTEMPTS = 20
INTERVAL_MS = 12000

def units(value):
    n = decimal.Decimal(str(value)) / UNIT
    if not n.is_finite() or n != n.to_integral_value() or n < 0:
        raise ValueError('Budget must be nonnegative and exactly representable')
    return int(n)

class DryRun:
    def __init__(self, directory, run_id, budget='1.37445'):
        if not isinstance(run_id,str) or not run_id.strip(): raise ValueError('Explicit new run ID required')
        self.path=pathlib.Path(directory)
        # Exclusive creation: existing/stopped runs cannot be overwritten/resumed.
        self.path.mkdir(parents=True, exist_ok=False)
        self.db=sqlite3.connect(self.path/'journal.sqlite',timeout=5)
        self.db.executescript('''
          CREATE TABLE run (id TEXT PRIMARY KEY, state TEXT NOT NULL, budget INTEGER NOT NULL, clock INTEGER NOT NULL);
          CREATE TABLE attempts (id INTEGER PRIMARY KEY, logical_id TEXT NOT NULL, reserved INTEGER NOT NULL, start_ms INTEGER NOT NULL, outcome TEXT NOT NULL, raw TEXT, finish_reason TEXT, model TEXT, usage TEXT, latency_ms INTEGER);
        ''')
        self.db.execute('INSERT INTO run VALUES (?, ?, ?, ?)',(run_id,'running',units(budget),0));self.db.commit()
    def reserve(self, logical_id):
        if not isinstance(logical_id,str) or not logical_id: raise ValueError('Logical ID required')
        self.db.execute('BEGIN IMMEDIATE')
        try:
            state,budget,clock=self.db.execute('SELECT state,budget,clock FROM run').fetchone()
            if state!='running': raise RuntimeError('Stopped/complete run cannot continue')
            count,total,last=self.db.execute('SELECT count(*),coalesce(sum(reserved),0),max(start_ms) FROM attempts').fetchone()
            if count>=MAX_ATTEMPTS or total+units(PER_ATTEMPT)>budget:
                self.db.execute("UPDATE run SET state='stopped'");self.db.commit()
                raise RuntimeError('Attempt/budget cap reached; explicit new run required')
            start=max(clock,0 if last is None else last+INTERVAL_MS)
            cursor=self.db.execute('INSERT INTO attempts(logical_id,reserved,start_ms,outcome) VALUES (?,?,?,?)',(logical_id,units(PER_ATTEMPT),start,'reserved'))
            self.db.execute('UPDATE run SET clock=?',(start,));self.db.commit();return cursor.lastrowid
        except Exception:
            if self.db.in_transaction:self.db.rollback()
            raise
    def attempt(self, logical_id, fixture):
        # The reservation is durably committed BEFORE inspecting/executing any
        # simulation outcome. Crashes/timeouts/errors consume it, without refund.
        ident=self.reserve(logical_id)
        self.db.execute('BEGIN IMMEDIATE')
        if self.db.execute('SELECT state FROM run').fetchone()[0] != 'running':
            self.db.execute("UPDATE attempts SET outcome='stopped_before_simulation' WHERE id=?",(ident,))
            self.db.commit();return ident
        outcome=fixture.get('outcome','success')
        if outcome not in ['success','timeout','error','rate_limit']:
            outcome='error'
        latency=fixture.get('simulatedLatencyMs',0)
        if not isinstance(latency,int) or isinstance(latency,bool) or latency<0: latency=0;outcome='error'
        raw=fixture.get('rawResponse')
        if raw is not None and not isinstance(raw,str): raw=None;outcome='error'
        self.db.execute('''UPDATE attempts SET outcome=?,raw=?,finish_reason=?,model=?,usage=?,latency_ms=? WHERE id=?''',(outcome,raw,fixture.get('finish_reason'),fixture.get('model'),json.dumps(fixture['usage']) if fixture.get('usage') is not None else None,latency,ident))
        self.db.execute('UPDATE run SET clock=clock+?',(latency,));self.db.commit();return ident
    def stop(self):
        self.db.execute("UPDATE run SET state='stopped'");self.db.commit()
    def finish(self):
        self.db.execute("UPDATE run SET state='complete' WHERE state='running'");self.db.commit()
    def snapshot(self):
        run_id,state,budget,clock=self.db.execute('SELECT * FROM run').fetchone()
        records=[]
        for row in self.db.execute('SELECT * FROM attempts ORDER BY id'):
            i,logical,reserved,start,outcome,raw,finish,model,usage,latency=row
            records.append({'attempt':i,'logicalSample':logical,'reservedPlannedUsd':str(decimal.Decimal(reserved)*UNIT),'virtualStartMs':start,'outcome':outcome,'rawResponse':raw,'finish_reason':finish,'model':model,'usage':json.loads(usage) if usage is not None else None,'latencyMs':latency,'latencyKind':'simulated','usageKind':'fixture_not_measured' if usage else 'missing','actualCostUsd':None})
        return {'dryRun':True,'liveAuthorized':False,'runId':run_id,'state':state,'attemptLimit':MAX_ATTEMPTS,'attemptsUsed':len(records),'logicalSamplesUsed':len({r['logicalSample'] for r in records}),'virtualClockMs':clock,'budgetPlannedUsd':str(decimal.Decimal(budget)*UNIT),'reservedPlannedUsd':str(sum((decimal.Decimal(r['reservedPlannedUsd']) for r in records),decimal.Decimal(0))),'actualCostUsd':None,'billingVerified':False,'reservationKind':'conditional_assumption_not_verified_live_ceiling','reservationAssumptions':{'nonImageInputTokens':10000,'imageTokens':1105,'outputTokens':4096,'inputUsdPerMillion':'2.50','outputUsdPerMillion':'10','excludes':['cloud','tax','exchange']},'attempts':records}
    def export(self):
        path=self.path/'result.json'
        with path.open('x') as stream:stream.write(json.dumps(self.snapshot(),ensure_ascii=False,indent=2)+'\n')
        return path
    def close(self):self.db.close()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--new-run-dir',required=True);p.add_argument('--run-id',required=True)
    p.add_argument('--fixtures',required=True);p.add_argument('--budget',default='1.37445')
    a=p.parse_args();fixtures=json.loads(pathlib.Path(a.fixtures).read_text())
    if fixtures.get('dryRun') is not True or not isinstance(fixtures.get('attempts'),list):p.error('Only explicit dry-run fixtures accepted')
    runner=DryRun(a.new_run_dir,a.run_id,a.budget)
    try:
        for item in fixtures['attempts']:
            try:runner.attempt(item['logicalSample'],item)
            except RuntimeError:break
        runner.finish();print(runner.export())
    finally:runner.close()
if __name__=='__main__':main()
