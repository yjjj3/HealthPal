'use strict';
const MAX_BODY_BYTES = 15 * 1024 * 1024;
function validatePayload(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('invalid');
  const allowed = ['model', 'messages', 'max_tokens', 'temperature', 'response_format'];
  if (Object.keys(body).some((key) => !allowed.includes(key)) || body.model !== 'gpt-4o') throw new Error('invalid');
  if (!Array.isArray(body.messages) || body.messages.length < 1 || body.messages.length > 22) throw new Error('invalid');
  if (!Number.isInteger(body.max_tokens) || body.max_tokens < 1 || body.max_tokens > 4096) throw new Error('invalid');
  if (!Number.isFinite(body.temperature) || body.temperature < 0 || body.temperature > 1) throw new Error('invalid');
  if (Buffer.byteLength(JSON.stringify(body)) > MAX_BODY_BYTES) throw new Error('invalid');
  for (const message of body.messages) {
    if (!message || !['system','user','assistant'].includes(message.role)) throw new Error('invalid');
    if (typeof message.content === 'string') {
      if (!message.content.trim() || message.content.length > 60000) throw new Error('invalid');
    } else if (Array.isArray(message.content) && message.role === 'user' && message.content.length <= 3) {
      if (!message.content.length) throw new Error('invalid');
      for (const item of message.content) {
        if (item?.type === 'text' && typeof item.text === 'string' && item.text.length <= 60000) continue;
        if (item?.type === 'image_url' && typeof item.image_url?.url === 'string' &&
          /^data:image\/(jpeg|png|gif|webp);base64,[A-Za-z0-9+/]+=*$/.test(item.image_url.url) &&
          ['low','high','auto'].includes(item.image_url.detail)) continue;
        throw new Error('invalid'); // Never fetch user-supplied URLs.
      }
    } else throw new Error('invalid');
  }
  if (body.response_format != null) {
    const format = body.response_format;
    if (format.type !== 'json_schema' || format.json_schema?.strict !== true ||
      !['nutrition_analysis','prescription_recognition'].includes(format.json_schema.name) ||
      !format.json_schema.schema || typeof format.json_schema.schema !== 'object') throw new Error('invalid');
  }
  return body;
}
// Additive, bounded projection of provider metering only. No headers, IDs,
// request body, credential fields or arbitrary provider metadata are returned.
function metering(result) {
  const u = result?.usage;
  const valid = (n) => Number.isSafeInteger(n) && n >= 0;
  const usage = u && valid(u.prompt_tokens) && valid(u.completion_tokens) &&
    valid(u.total_tokens) && u.prompt_tokens + u.completion_tokens === u.total_tokens
    ? {prompt_tokens: u.prompt_tokens, completion_tokens: u.completion_tokens, total_tokens: u.total_tokens}
    : null;
  const model = typeof result?.model === 'string' && /^gpt-4o-\d{4}-\d{2}-\d{2}$/.test(result.model)
    ? result.model : null; // A returned alias alone is not a resolved snapshot.
  const finish = result?.choices?.[0]?.finish_reason;
  return {usage, resolved_model: model,
    finish_reason: ['stop','length','tool_calls','content_filter','function_call'].includes(finish) ? finish : null};
}
function createHandler({verifyToken, consumeQuota, apiKey, fetchImpl = fetch}) {
  return async (req, res) => {
    res.set('Cache-Control', 'no-store');
    if (req.method !== 'POST') return res.status(405).json({error: {code: 'method_not_allowed'}});
    const bearer = /^Bearer (\S+)$/.exec(req.get('Authorization') || '');
    if (!bearer) return res.status(401).json({error: {code: 'unauthenticated'}});
    let identity;
    try { identity = await verifyToken(bearer[1]); }
    catch (_) { return res.status(401).json({error: {code: 'unauthenticated'}}); }
    if (!identity?.uid || identity.firebase?.sign_in_provider === 'anonymous') return res.status(403).json({error: {code: 'unauthenticated'}});
    let payload;
    try { payload = validatePayload(req.body); }
    catch (_) { return res.status(400).json({error: {code: 'invalid_request'}}); }
    try {
      const key = apiKey();
      if (!key) return res.status(503).json({error: {code: 'not_configured'}});
      if (!await consumeQuota(identity.uid)) return res.status(429).json({error: {code: 'insufficient_quota'}});
      const upstream = await fetchImpl('https://api.openai.com/v1/chat/completions', {
        method: 'POST', headers: {'Content-Type': 'application/json', Authorization: `Bearer ${key}`},
        body: JSON.stringify(payload), signal: AbortSignal.timeout(45000),
      });
      if (!upstream.ok) {
        const status = [401,403,429].includes(upstream.status) ? upstream.status : 502;
        let code = 'upstream_failure';
        if (upstream.status === 429) {
          try { if ((await upstream.json()).error?.code === 'insufficient_quota') code = 'insufficient_quota'; } catch (_) {}
        }
        return res.status(status).json({error: {code}});
      }
      const result = await upstream.json();
      // Return the response contract, never headers, credentials or full request logs.
      return res.status(200).json({choices: result.choices, ...metering(result)});
    } catch (_) { return res.status(503).json({error: {code: 'upstream_unavailable'}}); }
  };
}
module.exports = {validatePayload, createHandler};
