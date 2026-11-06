import test from 'node:test';
import assert from 'node:assert/strict';
import {downloadInventory,chooseNumbers,batches} from '../prototype/downloads.mjs';
const numbers=(n,start=1)=>Array.from({length:n},(_,i)=>start+i);
test('Next means after the newest locally downloaded article, never oldest missing history',()=>{
 const available=numbers(3000),known=numbers(500,501);
 const plan=downloadInventory(available,known);
 assert.equal(plan.highWater,1000);assert.equal(plan.pending.length,2000);assert.equal(plan.olderCount,500);
 assert.deepEqual(chooseNumbers(plan.pending,500,'next'),numbers(500,1001));
 assert.deepEqual(chooseNumbers(plan.pending,500,'latest'),numbers(500,2501));
});
test('Latest advances the cursor, skipped older messages remain available through Older',()=>{
 const available=numbers(3000),latest=chooseNumbers(available,500,'latest');
 assert.equal(downloadInventory(available,latest).pending.length,0);
 const old=downloadInventory(available,latest,3000,true);
 assert.equal(old.pending.length,2500);assert.deepEqual(chooseNumbers(old.pending,500,'latest'),numbers(500,2001));
 assert.deepEqual(downloadInventory(numbers(3100),latest).pending,numbers(100,3001));
});
test('exact counts handle gaps, expiration, duplicate numbers and persisted cursors',()=>{
 const plan=downloadInventory([1,2,2,10,11,20,40],[2,10],20);
 assert.deepEqual(plan.pending,[40]);assert.equal(plan.olderCount,3);
 assert.equal(downloadInventory([],[],100).pending.length,0);
 assert.equal(downloadInventory(numbers(500),[]).pending.length,500);
 assert.equal(downloadInventory(numbers(501),[]).pending.length,501);
});
test('All and custom counts are served in bounded batches with no overlap',()=>{
 const pending=numbers(1701),all=chooseNumbers(pending,'all','next');
 assert.deepEqual(batches(all).map(b=>b.length),[500,500,500,201]);
 assert.deepEqual(batches(all).flat(),pending);
 assert.equal(chooseNumbers(pending,1000,'next').length,1000);
 assert.equal(chooseNumbers(pending,9000,'latest').length,1701);
});
