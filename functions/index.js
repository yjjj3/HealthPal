'use strict';
const {onRequest} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore} = require('firebase-admin/firestore');
const {createHandler} = require('./gateway');
initializeApp();
const openAIKey = defineSecret('OPENAI_API_KEY');
async function consumeQuota(uid) {
  const db = getFirestore();
  const userRef = db.doc(`_ai_usage/users_${uid}`);
  const globalRef = db.doc('_ai_usage/global');
  const now = Date.now();
  const day = new Date(now).toISOString().slice(0,10);
  const minute = Math.floor(now / 60000);
  return db.runTransaction(async (tx) => {
    const [user, global] = await Promise.all([tx.get(userRef), tx.get(globalRef)]);
    const u = user.data() || {}, g = global.data() || {};
    const userDaily = u.day === day ? u.daily || 0 : 0;
    const globalDaily = g.day === day ? g.daily || 0 : 0;
    const userMinute = u.minute === minute ? u.requests || 0 : 0;
    if (userDaily >= 50 || globalDaily >= 1000 || userMinute >= 10) return false;
    tx.set(userRef, {day, daily:userDaily+1, minute, requests:userMinute+1});
    tx.set(globalRef, {day, daily:globalDaily+1});
    return true;
  });
}
exports.healthAI = onRequest({region:'asia-east1', timeoutSeconds:60, memory:'256MiB',
  maxInstances:2, concurrency:10, cors:true, secrets:[openAIKey]}, createHandler({
    verifyToken: (token) => getAuth().verifyIdToken(token, true), consumeQuota,
    apiKey: () => openAIKey.value(),
  }));
