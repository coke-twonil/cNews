import test from 'node:test';
import assert from 'node:assert/strict';
import {mergeHeaders} from '../prototype/nntp.mjs';
import {messageTree} from '../prototype/model.mjs';
const row=(id,number,references=[])=>({id,number,references,subject:'same',author:'甲',createdAt:'2026-11-05T00:00:00Z'});
test('references build nested branches, missing ancestors connect siblings, subjects do not',()=>{
 const ts=mergeHeaders([], [row('a',1),row('b',2,['a']),row('c',3,['a','b']),row('d',4,['a']),row('e',5),row('f',6,['missing']),row('g',7,['missing'])],'live','chat');
 assert.equal(ts.length,3);
 const t=ts.find(t=>t.messages.some(m=>m.id==='a'));
 assert.deepEqual(messageTree(t).map(e=>[e.message.id,e.depth]),[['a',0],['b',1],['c',2],['d',1]]);
});
test('refresh keeps bodies/read/star, new messages unread, other servers untouched',()=>{
 let ts=mergeHeaders([{id:'demo',server:'demo',group:'chat',messages:[]}],[row('a',1)],'live','chat');
 const live=ts.find(t=>t.server==='live');live.star=true;Object.assign(live.messages[0],{read:true,body:'真實中文',bodyLoaded:true});
 ts=mergeHeaders(ts,[row('a',1),row('b',2,['a'])],'live','chat');
 const next=ts.find(t=>t.server==='live');assert.equal(ts[0].id,'demo');assert.equal(next.star,true);assert.equal(next.messages[0].body,'真實中文');assert.equal(next.messages[0].read,true);assert.equal(next.messages[1].read,false);
});

test('loading an older parent joins cached branches without resurrecting duplicates',async()=>{
 const {withoutSupersededThreads}=await import('../prototype/nntp.mjs');
 const {mergeRepository}=await import('../prototype/model.mjs');
 const branches=mergeHeaders([],[row('a',2,['missing-a']),row('b',3,['missing-b'])],'live','chat');
 const repository={servers:[{id:'live',mode:'nntp'}],threads:branches};
 const threads=mergeHeaders(branches,[row('missing-b',1,['missing-a'])],'live','chat');
 assert.equal(threads.length,1);
 const snapshot={...repository,threads};
 const saved=mergeRepository(snapshot,withoutSupersededThreads(snapshot,repository));
 assert.equal(saved.threads.length,1);
 assert.equal(saved.threads[0].messages.length,3);
});
test('MIME cache upgrades old text-only articles and reloads omitted image bytes',async()=>{
 const {needsArticleContent,applyArticleContent}=await import('../prototype/nntp.mjs');
 const m={bodyLoaded:true,body:'舊快取',read:true,images:[]};
 assert.equal(needsArticleContent(m),true);
 applyArticleContent(m,{body:'中文',images:['data:image/png;base64,fixture'],contentVersion:3});
 assert.equal(needsArticleContent(m),false);assert.equal(m.read,true);assert.equal(m.imageCount,1);
 const restored=JSON.parse(JSON.stringify(m,(k,v)=>k==='images'?[]:v));
 assert.equal(needsArticleContent(restored),true);
 const text={};applyArticleContent(text,{body:'plain',images:[],contentVersion:3});assert.equal(needsArticleContent(text),false);
});
