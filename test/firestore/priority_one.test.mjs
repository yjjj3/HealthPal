import {readFileSync} from 'node:fs';
import {before, after, beforeEach, test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, collection, setDoc, getDoc, getDocs, updateDoc, deleteDoc,
  writeBatch, runTransaction, query, where, orderBy, limit, Timestamp, serverTimestamp, increment} from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-healthpal-priority1',
    firestore: {host: '127.0.0.1', port: 8087,
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });
const dbFor = (uid) => env.authenticatedContext(uid,
  {email: `${uid}@example.com`, email_verified: true}).firestore();
const grants = {'血糖數據': true, '血壓數據': false, '用藥記錄': true};
const noGrants = {'血糖數據': false, '血壓數據': false, '用藥記錄': false};
async function seed(data) {
  await env.withSecurityRulesDisabled(async (context) => {
    for (const [path, value] of Object.entries(data)) await setDoc(doc(context.firestore(), path), value);
  });
}
async function invite(options = {}) {
  await seed({'family_invites/invite': {invitedBy: 'alice', invitedToEmail: 'bob@example.com',
    sharedData: grants, status: 'pending',
    expiresAt: Timestamp.fromMillis(Date.now() + 3600000), ...options}});
}
function acceptBatch(db, {uid = 'bob', partial = false, sharing = noGrants} = {}) {
  const batch = writeBatch(db);
  batch.update(doc(db, 'family_invites/invite'), {
    status: 'accepted', acceptedBy: uid, respondedAt: serverTimestamp()});
  batch.set(doc(db, `users/alice/family_members/${uid}`), {
    userId: uid, inviteId: 'invite', sharedData: grants});
  if (!partial) batch.set(doc(db, `users/${uid}/family_members/alice`), {
    userId: 'alice', inviteId: 'invite', sharedData: sharing});
  return batch.commit();
}
async function acceptedFamily() {
  await invite();
  await assertSucceeds(acceptBatch(dbFor('bob')));
  await seed({
    'users/alice/health_records/sugar': {category: '血糖', value: '100 mg/dL'},
    'users/alice/health_records/pressure': {category: '血壓', value: '120/80 mmHg'},
    'users/alice/medicine/pill': {name: 'test', frequency: '每天1次', times_status: [false]},
    'users/bob/health_records/sugar': {category: '血糖', value: '90 mg/dL'},
  });
}

test('settings are readable/writable only by the owner', async () => {
  const alice = dbFor('alice');
  await assertSucceeds(setDoc(doc(alice, 'users/alice/settings/notifications'), {all: false}));
  await assertSucceeds(getDoc(doc(alice, 'users/alice/settings/notifications')));
  await assertFails(getDoc(doc(dbFor('bob'), 'users/alice/settings/notifications')));
  await assertFails(setDoc(doc(dbFor('bob'), 'users/alice/settings/notifications'), {all: true}));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users/alice/settings/notifications')));
});
test('valid recipient atomically accepts and creates both relationships', async () => {
  await invite();
  await assertSucceeds(acceptBatch(dbFor('bob')));
  const grant = await getDoc(doc(dbFor('bob'), 'users/alice/family_members/bob'));
  assert.deepEqual(grant.data().sharedData, grants);
  await assertFails(updateDoc(doc(dbFor('bob'), 'family_invites/invite'), {sharedData: noGrants}));
});
test('wrong recipient, expired invite, partial acceptance and forged sharing are denied', async () => {
  await invite();
  await assertFails(acceptBatch(dbFor('mallory'), {uid: 'mallory'}));
  await assertFails(acceptBatch(dbFor('bob'), {partial: true}));
  await assertFails(acceptBatch(dbFor('bob'), {sharing: grants}));
  await assertFails(setDoc(doc(dbFor('mallory'), 'users/alice/family_members/mallory'),
    {userId: 'mallory', inviteId: 'invite', sharedData: grants}));
  await invite({expiresAt: Timestamp.fromMillis(Date.now() - 3600000)});
  await assertFails(acceptBatch(dbFor('bob')));
});
test('code invitation can be redeemed once and cannot be overwritten', async () => {
  const alice = dbFor('alice');
  await assertSucceeds(setDoc(doc(alice, 'family_invites/invite'), {
    invitedBy: 'alice', inviteCode: '123456', status: 'pending', sharedData: grants,
    expiresAt: Timestamp.fromMillis(Date.now() + 3600000)}));
  await assertSucceeds(acceptBatch(dbFor('bob')));
  await assertFails(acceptBatch(dbFor('mallory'), {uid: 'mallory'}));
  await assertFails(deleteDoc(doc(alice, 'family_invites/invite')));
});
test('family can read only owner-granted categories, never modify grants', async () => {
  await acceptedFamily();
  const bob = dbFor('bob');
  await assertSucceeds(getDocs(query(collection(bob, 'users/alice/health_records'), where('category', '==', '血糖'))));
  await assertSucceeds(getDoc(doc(bob, 'users/alice/medicine/pill')));
  await assertFails(getDoc(doc(bob, 'users/alice/health_records/pressure')));
  await assertFails(getDocs(collection(bob, 'users/alice/health_records')));
  await assertFails(updateDoc(doc(bob, 'users/alice/family_members/bob'), {sharedData: {'血壓': true}}));
  await assertFails(getDoc(doc(dbFor('alice'), 'users/bob/health_records/sugar')));
  await assertFails(getDoc(doc(dbFor('mallory'), 'users/alice/health_records/sugar')));
  await assertSucceeds(updateDoc(doc(dbFor('alice'), 'users/alice/family_members/bob'), {sharedData: noGrants}));
  await assertFails(getDoc(doc(bob, 'users/alice/health_records/sugar')));
});
test('removing either relationship revokes health sharing', async () => {
  await acceptedFamily();
  await assertSucceeds(deleteDoc(doc(dbFor('bob'), 'users/bob/family_members/alice')));
  await assertFails(getDoc(doc(dbFor('bob'), 'users/alice/health_records/sugar')));
});
test('legacy relationship without a consumed invitation cannot authorize sharing', async () => {
  await seed({
    'users/alice/family_members/bob': {userId: 'bob', sharedData: grants},
    'users/bob/family_members/alice': {userId: 'alice', sharedData: grants},
    'users/alice/health_records/sugar': {category: '血糖'},
  });
  await assertFails(getDoc(doc(dbFor('bob'), 'users/alice/health_records/sugar')));
});
test('chat transaction writes message and unread atomically; repeated ID is a no-op', async () => {
  await seed({'chats/alice_bob': {members: ['alice', 'bob'], unread: {bob: 0}}});
  const alice = dbFor('alice');
  async function send(id, senderId = 'alice', chatId = 'alice_bob') {
    return runTransaction(alice, async (tx) => {
      const message = doc(alice, `chats/${chatId}/messages/${id}`);
      if ((await tx.get(message)).exists()) return;
      tx.set(message, {senderId, text: 'hello', timestamp: serverTimestamp()});
      tx.update(doc(alice, `chats/${chatId}`), {lastMessage: 'hello', 'unread.bob': increment(1)});
    });
  }
  await assertSucceeds(send('id'));
  await assertSucceeds(send('id'));
  assert.equal((await getDoc(doc(alice, 'chats/alice_bob'))).data().unread.bob, 1);
  await assertFails(send('forged', 'bob'));
  assert.equal((await getDoc(doc(alice, 'chats/alice_bob/messages/forged'))).exists(), false);
  await assertFails(updateDoc(doc(alice, 'chats/alice_bob'), {members: ['alice', 'mallory']}));
});


test('bounded queries preserve owner and category-based family authorization', async () => {
  await acceptedFamily();
  await seed({
    'users/alice/health_records/sugar': {category: '血糖', value: '100 mg/dL', record_time: Timestamp.now()},
    'users/alice/health_records/pressure': {category: '血壓', value: '120/80 mmHg', record_time: Timestamp.now()},
    'chats/alice_bob': {members: ['alice', 'bob'], lastTime: Timestamp.now()},
    'chats/alice_bob/messages/one': {senderId: 'alice', text: 'hello', timestamp: Timestamp.now()},
  });
  const bob = dbFor('bob');
  const health = collection(bob, 'users/alice/health_records');
  const sugar = await assertSucceeds(getDocs(query(health,
    where('category', '==', '血糖'), orderBy('record_time', 'desc'), limit(1))));
  assert.equal(sugar.docs.length, 1);
  await assertFails(getDocs(query(health, orderBy('record_time', 'desc'), limit(20))));
  const own = await assertSucceeds(getDocs(query(collection(dbFor('alice'), 'users/alice/health_records'),
    orderBy('record_time', 'desc'), limit(50))));
  assert.equal(own.docs.length, 2);
  const chats = await assertSucceeds(getDocs(query(collection(bob, 'chats'),
    where('members', 'array-contains', 'bob'), orderBy('lastTime', 'desc'), limit(50))));
  assert.equal(chats.docs.length, 1);
  const messages = await assertSucceeds(getDocs(query(collection(bob, 'chats/alice_bob/messages'),
    orderBy('timestamp', 'desc'), limit(50))));
  assert.equal(messages.docs.length, 1);
  await assertFails(getDocs(query(collection(dbFor('mallory'), 'chats/alice_bob/messages'),
    orderBy('timestamp', 'desc'), limit(50))));
});
