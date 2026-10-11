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
    sharedData: noGrants, status: 'pending',
    expiresAt: Timestamp.fromMillis(Date.now() + 3600000), ...options}});
}
function acceptBatch(db, {uid = 'bob', partial = false, sharing = noGrants} = {}) {
  const batch = writeBatch(db);
  batch.update(doc(db, 'family_invites/invite'), {
    status: 'accepted', acceptedBy: uid, respondedAt: serverTimestamp()});
  batch.set(doc(db, `users/alice/family_members/${uid}`), {
    userId: uid, inviteId: 'invite', sharedData: noGrants});
  if (!partial) batch.set(doc(db, `users/${uid}/family_members/alice`), {
    userId: 'alice', inviteId: 'invite', sharedData: sharing});
  return batch.commit();
}
async function acceptedFamily() {
  await invite();
  await assertSucceeds(acceptBatch(dbFor('bob')));
  await seed({
    'users/alice/shared_profile/bob': {version: 1, inviteId: 'invite', consent: {}, values: {},
      records: {'血糖': true, '血壓': false, '用藥': true}, updatedAt: Timestamp.now()},
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
  const grant = await getDoc(doc(dbFor('alice'), 'users/alice/family_members/bob'));
  await assertFails(getDoc(doc(dbFor('bob'), 'users/alice/family_members/bob')));
  assert.deepEqual(grant.data().sharedData, noGrants);
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
    invitedBy: 'alice', inviteCode: '123456', status: 'pending', sharedData: noGrants,
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
  await assertSucceeds(updateDoc(doc(dbFor('alice'), 'users/alice/shared_profile/bob'),
    {records: {}, updatedAt: serverTimestamp()}));
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

test('prescription commit receipt survives medicine deletion and stays owner-only', async () => {
  const alice = dbFor('alice');
  const receipt = doc(alice, 'users/alice/settings/prescription_save_reserved');
  const medicine = doc(alice, 'users/alice/medicine/reserved');
  await assertSucceeds(runTransaction(alice, async (tx) => {
    assert.equal((await tx.get(receipt)).exists(), false);
    assert.equal((await tx.get(medicine)).exists(), false);
    tx.set(receipt, {medicine_ids: ['reserved'], committed_at: Timestamp.now()});
    tx.set(medicine, {name: 'fake', frequency: '每天1次', times_status: [false]});
  }));
  await assertSucceeds(deleteDoc(medicine));
  assert.equal((await assertSucceeds(getDoc(receipt))).exists(), true);
  await assertFails(getDoc(doc(dbFor('bob'), receipt.path)));
  await assertFails(deleteDoc(doc(dbFor('bob'), receipt.path)));
});

// Fake identities and synthetic profile data only; no production project.
test('private profile cannot be read by authenticated strangers or family', async () => {
  await acceptedFamily();
  await seed({'users/alice': {fullName: 'Synthetic owner', email: 'alice@example.com',
    phoneNumber: 'synthetic-phone', allergies: 'synthetic-allergy'}});
  await assertSucceeds(getDoc(doc(dbFor('alice'), 'users/alice')));
  await assertFails(getDoc(doc(dbFor('bob'), 'users/alice')));
  await assertFails(getDoc(doc(dbFor('mallory'), 'users/alice')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users/alice')));
  const anonymous = env.authenticatedContext('alice',
    {firebase: {sign_in_provider: 'anonymous'}}).firestore();
  await assertFails(getDoc(doc(anonymous, 'users/alice')));
});

test('per-viewer profile projection rejects unselected values, unknown keys and forged consent', async () => {
  await acceptedFamily();
  await seed({'users/alice': {fullName: 'Synthetic owner', email: 'alice@example.com',
    allergies: 'synthetic-allergy'}});
  const ref = doc(dbFor('alice'), 'users/alice/shared_profile/bob');
  const shared = {version: 1, inviteId: 'invite', consent: {allergies: true},
    values: {allergies: 'synthetic-allergy'}, records: {}, updatedAt: serverTimestamp()};
  await assertSucceeds(setDoc(ref, shared));
  const visible = (await assertSucceeds(getDoc(doc(dbFor('bob'), ref.path)))).data();
  assert.deepEqual(visible.values, {allergies: 'synthetic-allergy'});
  assert.equal('email' in visible.values, false);
  await assertFails(getDoc(doc(dbFor('mallory'), ref.path)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), ref.path)));
  await assertFails(setDoc(doc(dbFor('bob'), ref.path), shared));
  await assertFails(setDoc(ref, {...shared, values: {...shared.values, email: 'alice@example.com'}}));
  await assertFails(setDoc(ref, {...shared, consent: {allergies: true, secret: true}}));
  await assertFails(setDoc(ref, {...shared, values: {allergies: 'forged'}}));
  await assertFails(setDoc(ref, {...shared, unexpected: true}));
  await assertFails(setDoc(ref, {...shared, consent: {allergies: 'true'}}));
  await assertSucceeds(setDoc(ref, {...shared, consent: {}, values: {}}));
  assert.deepEqual((await getDoc(doc(dbFor('bob'), ref.path))).data().values, {});
  await assertSucceeds(deleteDoc(doc(dbFor('alice'), 'users/alice/family_members/bob')));
  await assertFails(getDoc(doc(dbFor('bob'), ref.path)));
  await assertFails(setDoc(ref, shared));
});

test('missing profile grants and malformed legacy projections never imply consent', async () => {
  await acceptedFamily();
  const owner = dbFor('alice'); const bob = dbFor('bob');
  await assertSucceeds(deleteDoc(doc(owner, 'users/alice/shared_profile/bob')));
  // Missing doc is readable as "not shared", but private data and records remain denied.
  assert.equal((await assertSucceeds(getDoc(doc(bob, 'users/alice/shared_profile/bob')))).exists(), false);
  await assertFails(getDoc(doc(bob, 'users/alice/medicine/pill')));
  await assertSucceeds(updateDoc(doc(owner, 'users/alice/family_members/bob'),
    {sharedData: {'用藥': true}}));
  await assertFails(getDoc(doc(bob, 'users/alice/medicine/pill')));
  await seed({'users/alice/shared_profile/bob': {consent: {email: true}, values: {email: 'synthetic'}}});
  await assertFails(getDoc(doc(bob, 'users/alice/shared_profile/bob')));
});

test('projection withdrawal deletes values and both membership removals deny direct reads', async () => {
  await acceptedFamily();
  await seed({'users/alice': {email: 'alice@example.com'}});
  const alice = dbFor('alice'); const bob = dbFor('bob');
  const ref = doc(alice, 'users/alice/shared_profile/bob');
  const grant = {version: 1, inviteId: 'invite', consent: {email: true},
    values: {email: 'alice@example.com'}, records: {'用藥': true}, updatedAt: serverTimestamp()};
  await assertSucceeds(setDoc(ref, grant));
  await assertFails(updateDoc(ref, {consent: {email: false}, updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {records: {'unknown': true}, updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {records: {'用藥': 'true'}, updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {inviteId: 'forged', updatedAt: serverTimestamp()}));
  await assertFails(getDocs(collection(bob, 'users/alice/shared_profile')));
  const anonymous = env.authenticatedContext('bob', {firebase: {sign_in_provider: 'anonymous'}}).firestore();
  await assertFails(getDoc(doc(anonymous, ref.path)));
  await assertSucceeds(deleteDoc(doc(bob, 'users/bob/family_members/alice')));
  await assertFails(getDoc(doc(bob, ref.path)));
  await assertFails(getDoc(doc(bob, 'users/alice/medicine/pill')));
  await seed({'users/bob/family_members/alice': {userId: 'alice', inviteId: 'new-invite', sharedData: {}}});
  await seed({'users/alice/family_members/bob': {userId: 'bob', inviteId: 'new-invite', sharedData: {}},
    'family_invites/new-invite': {invitedBy: 'alice', acceptedBy: 'bob', status: 'accepted'}});
  await assertFails(getDoc(doc(bob, ref.path)));
  await assertFails(getDoc(doc(bob, 'users/alice/medicine/pill')));
});

test('invitation and chat function without either private profile being readable cross-account', async () => {
  await invite();
  const bob = dbFor('bob'); const alice = dbFor('alice');
  await assertSucceeds(getDoc(doc(bob, 'family_invites/invite')));
  await assertFails(getDoc(doc(dbFor('mallory'), 'family_invites/invite')));
  await assertFails(getDocs(collection(dbFor('mallory'), 'family_invites')));
  await assertSucceeds(getDocs(query(collection(bob, 'family_invites'),
    where('invitedToEmail', '==', 'bob@example.com'), where('status', '==', 'pending'))));
  await assertSucceeds(acceptBatch(bob));
  await assertSucceeds(setDoc(doc(alice, 'chats/alice_bob'),
    {members: ['alice', 'bob'], memberNames: {alice: '家人', bob: '家人'}}));
  await assertSucceeds(setDoc(doc(bob, 'chats/alice_bob/messages/one'),
    {senderId: 'bob', senderName: '家人', text: 'synthetic message'}));
  await assertSucceeds(getDoc(doc(alice, 'chats/alice_bob/messages/one')));
  await assertFails(getDoc(doc(bob, 'users/alice')));
  await assertFails(getDoc(doc(alice, 'users/bob')));
  await assertFails(setDoc(doc(alice, 'family_invites/forged'), {invitedBy: 'bob',
    status: 'pending', sharedData: noGrants, expiresAt: Timestamp.fromMillis(Date.now() + 3600000)}));
  await assertFails(setDoc(doc(alice, 'family_invites/injected'), {invitedBy: 'alice',
    inviterName: 'Synthetic private name', status: 'pending', sharedData: noGrants,
    expiresAt: Timestamp.fromMillis(Date.now() + 3600000)}));
});

test('removal transaction reads version and deletes both sides; mismatched reverse is denied', async () => {
  await acceptedFamily();
  const alice = dbFor('alice');
  const mine = doc(alice, 'users/alice/family_members/bob');
  const other = doc(alice, 'users/bob/family_members/alice');
  const projection = doc(alice, 'users/alice/shared_profile/bob');
  const remove = () => runTransaction(alice, async (tx) => {
    const member = await tx.get(mine);
    const shared = await tx.get(projection);
    assert.equal(member.data().inviteId, 'invite');
    tx.delete(mine); tx.delete(other);
    if (shared.exists() && shared.data().inviteId === member.data().inviteId) tx.delete(projection);
  });
  await seed({'users/bob/family_members/alice': {userId: 'alice', inviteId: 'new-invite', sharedData: {}}});
  await assertFails(getDoc(doc(dbFor('bob'), 'users/alice/shared_profile/bob')));
  await assertFails(remove());
  assert.equal((await getDoc(mine)).exists(), true);
  await seed({'users/bob/family_members/alice': {userId: 'alice', inviteId: 'invite', sharedData: {}}});
  await assertSucceeds(remove());
  assert.equal((await getDoc(mine)).exists(), false);
  await assertFails(getDoc(doc(dbFor('bob'), 'users/alice/medicine/pill')));
});

test('decline transaction cannot overwrite an already accepted invitation', async () => {
  await invite();
  const bob = dbFor('bob');
  const ref = doc(bob, 'family_invites/invite');
  await assertSucceeds(runTransaction(bob, async (tx) => {
    assert.equal((await tx.get(ref)).data().status, 'pending');
    tx.update(ref, {status: 'declined', acceptedBy: 'bob', respondedAt: serverTimestamp()});
  }));
  await invite();
  await assertSucceeds(acceptBatch(bob));
  await assertFails(updateDoc(ref, {status: 'declined', acceptedBy: 'bob', respondedAt: serverTimestamp()}));
});

test('legacy no-version removal works atomically and does not authorize newer reverse deletion', async () => {
  await seed({'users/alice/family_members/bob': {userId: 'bob'},
    'users/bob/family_members/alice': {userId: 'alice', inviteId: 'new-invite'}});
  const alice = dbFor('alice');
  const mine = doc(alice, 'users/alice/family_members/bob');
  const reverse = doc(alice, 'users/bob/family_members/alice');
  async function remove() {
    const batch = writeBatch(alice); batch.delete(mine); batch.delete(reverse);
    return batch.commit();
  }
  await assertFails(remove());
  assert.equal((await getDoc(mine)).exists(), true);
  await seed({'users/bob/family_members/alice': {userId: 'alice'}});
  await assertSucceeds(remove());
  await seed({'users/alice/family_members/bob': {userId: 'bob'}});
  await assertSucceeds(remove()); // Missing reverse doc must not strand the owner.
});
