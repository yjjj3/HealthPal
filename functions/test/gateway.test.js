'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createHandler, validatePayload} = require('../gateway');
const payload = () => ({model:'gpt-4o',messages:[{role:'user',content:'hello'}],max_tokens:100,temperature:0.3});
function response() { return {code:null,body:null,headers:{},set(k,v){this.headers[k]=v;return this;},status(code){this.code=code;return this;},json(body){this.body=body;return this;}}; }
function request(body=payload(),token='token',method='POST') {return {body,method,get:()=>token ? `Bearer ${token}` : undefined};}
function handler(overrides={}) {return createHandler({verifyToken:async()=>({uid:'alice'}),consumeQuota:async()=>true,apiKey:()=> 'server-secret',fetchImpl:async()=>({ok:true,json:async()=>({choices:[{message:{content:'ok'}}]})}),...overrides});}
test('unauthenticated and anonymous requests never reach upstream',async()=>{
  let calls=0;const run=handler({fetchImpl:async()=>{calls++;}});
  let res=response();await run(request(payload(),null),res);assert.equal(res.code,401);
  res=response();await handler({verifyToken:async()=>{throw new Error('token');}})(request(),res);assert.equal(res.code,401);
  res=response();await handler({verifyToken:async()=>({uid:'guest',firebase:{sign_in_provider:'anonymous'}})})(request(),res);assert.equal(res.code,403);
  assert.equal(calls,0);
});
test('reject arbitrary models, remote images, oversized token budgets and invalid roles',()=>{
  for(const bad of [{...payload(),model:'other'}, {...payload(),max_tokens:5000}, {...payload(),tools:[]},
    {...payload(),messages:[{role:'tool',content:'x'}]},
    {...payload(),messages:[{role:'user',content:[{type:'image_url',image_url:{url:'https://private-service',detail:'high'}}]}]},
    {...payload(),response_format:{type:'json_object'}}]) assert.throws(()=>validatePayload(bad));
});
test('authenticated request uses only server secret and quota identity from token',async()=>{
  let seen;
  const run=handler({consumeQuota:async(uid)=>{assert.equal(uid,'alice');return true;},fetchImpl:async(url,options)=>{
    seen=options;assert.equal(url,'https://api.openai.com/v1/chat/completions');return {ok:true,json:async()=>({choices:[{message:{content:'ok'}}],secret:'do not return'})};}});
  const res=response();await run(request(),res);assert.equal(res.code,200);assert.equal(seen.headers.Authorization,'Bearer server-secret');
  assert.equal(res.body.secret,undefined);assert.equal(res.headers['Cache-Control'],'no-store');
});
test('quota rejection does not call upstream',async()=>{
  const run=handler({consumeQuota:async()=>false,fetchImpl:async()=>assert.fail('must not call')});
  const res=response();await run(request(),res);assert.equal(res.code,429);assert.equal(res.body.error.code,'insufficient_quota');
});
test('invalid method and malformed body do not consume quota',async()=>{
  const run=handler({consumeQuota:async()=>assert.fail('must not consume')});
  let res=response();await run(request(payload(),'token','GET'),res);assert.equal(res.code,405);
  res=response();await run(request({model:'gpt-4o'}),res);assert.equal(res.code,400);
});
test('upstream failures cannot leak credentials or provider error text',async()=>{
  const run=handler({fetchImpl:async()=>({ok:false,status:500,json:async()=>({error:{message:'server-secret'}})})});
  const res=response();await run(request(),res);assert.equal(res.code,502);assert.ok(!JSON.stringify(res.body).includes('server-secret'));
});
test('missing secret and network failures have explicit failure states',async()=>{
  let res=response();await handler({apiKey:()=>''})(request(),res);assert.equal(res.code,503);
  res=response();await handler({fetchImpl:async()=>{throw new Error('network secret');}})(request(),res);assert.equal(res.code,503);
  assert.ok(!JSON.stringify(res.body).includes('network secret'));
});

test('offline prescription schema request matches gateway envelope, not content accuracy', async () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const fixture = (name) => JSON.parse(fs.readFileSync(path.join(__dirname, '../..', 'test/fixtures/prescription_eval', name), 'utf8'));
  const body = {
    model: 'gpt-4o', max_tokens: 4096, temperature: 0.1,
    messages: [{role: 'user', content: [
      {type: 'text', text: 'Synthetic contract only; no medical use'},
      {type: 'image_url', image_url: {url: 'data:image/png;base64,iVBORw0KGgo=', detail: 'high'}},
    ]}],
    response_format: {type: 'json_schema', json_schema: {name: 'prescription_recognition', strict: true, schema: fixture('production-response-schema.json')}},
  };
  assert.equal(validatePayload(body), body);
  const raw = fixture('oracle.json').predictions[0].raw;
  const run = handler({fetchImpl: async (_url, options) => {
    assert.deepEqual(JSON.parse(options.body), body);
    return {ok: true, json: async () => ({choices: [{message: {content: raw}}]})};
  }});
  const res = response(); await run(request(body), res);
  assert.equal(res.code, 200);
  assert.equal(res.body.choices[0].message.content, raw);
});

test('additive metering preserves choices and only safe usage/snapshot/finish fields', async () => {
  const choices = [{finish_reason: 'stop', message: {content: 'synthetic raw'}}];
  const run = handler({fetchImpl: async () => ({ok:true,json:async()=>({choices,
    model:'gpt-4o-2024-08-06', usage:{prompt_tokens:11,completion_tokens:7,total_tokens:18,private_extra:'synthetic forbidden'},
    id:'not forwarded',secret:'not forwarded'})})});
  const res=response();await run(request(),res);
  assert.deepEqual(res.body,{choices,usage:{prompt_tokens:11,completion_tokens:7,total_tokens:18},resolved_model:'gpt-4o-2024-08-06',finish_reason:'stop'});
});
test('legacy missing metadata and alias are null; invalid values do not leak', async () => {
  for (const extra of [{},{model:'gpt-4o'},
    {model:'synthetic-private-value',usage:{prompt_tokens:'1',completion_tokens:2,total_tokens:3}},
    {usage:{prompt_tokens:-1,completion_tokens:2,total_tokens:1}},
    {usage:{prompt_tokens:1,completion_tokens:2,total_tokens:9}},
    {usage:{prompt_tokens:1,completion_tokens:2}},
    {usage:{prompt_tokens:Number.MAX_SAFE_INTEGER+1,completion_tokens:0,total_tokens:Number.MAX_SAFE_INTEGER+1}}]) {
    const choices=[{message:{content:'same'}}];
    const run=handler({fetchImpl:async()=>({ok:true,json:async()=>({choices,...extra})})});
    const res=response();await run(request(),res);
    assert.deepEqual(res.body,{choices,usage:null,resolved_model:null,finish_reason:null});
  }
});
test('upstream error keeps legacy contract without fabricated metering', async () => {
  const run=handler({fetchImpl:async()=>({ok:false,status:429,json:async()=>({error:{code:'insufficient_quota'},usage:{prompt_tokens:1}})})});
  const res=response();await run(request(),res);
  assert.equal(res.code,429);assert.deepEqual(res.body,{error:{code:'insufficient_quota'}});
});
