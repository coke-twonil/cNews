import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareLiveReply,validSender,livePayload} from '../prototype/posting.mjs';
test('reply fetches missing parents, quotes four ancestors and excludes siblings/older fifth',async()=>{
 const messages=Array.from({length:6},(_,i)=>({id:`<${i}>`,parentId:i?`<${i-1}>`:null,references:Array.from({length:i},(_,n)=>`<${n}>`),author:`Author${i}`,body:`BODY${i}`,bodyLoaded:i===5,createdAt:'2026-11-05T00:00:00Z',time:'08:00',date:'05/11'}));
 const thread={id:'thread',server:'live',group:'test.test',subject:'測試',messages:[messages[5],{id:'sibling',body:'SIBLING',parentId:'<4>'}]},fetched=[];
 const d=await prepareLiveReply(thread,messages[5],async id=>{fetched.push(id);const m=messages.find(m=>m.id===id);return {id,body:m.body,meta:m}});
 assert.deepEqual(d.quoteMessageIds,['<5>','<4>','<3>','<2>']);assert.deepEqual(fetched,['<4>','<3>','<2>']);
 for(const i of [5,4,3,2])assert.ok(d.body.includes(`BODY${i}`));
 assert.ok(!d.body.includes('BODY1'));assert.ok(!d.body.includes('SIBLING'));assert.equal(d.replyTo,'<5>');assert.equal(d.references.at(-1),'<5>');
 assert.equal(thread.messages.length,2,'preparing quotes does not insert uncached headers into visible list');
});
test('live payload needs sender, keeps parent and limits photos',()=>{
 const d={group:'test.test',subject:'Subject',body:'Body',senderName:'測試',senderEmail:'test@example.invalid',postId:'fixed',replyTo:'<parent>',references:['<root>'],encoding:'big5'};
 assert.equal(validSender(d),true);assert.equal(livePayload(d,[]).replyTo,'<parent>');
 assert.throws(()=>livePayload({...d,senderEmail:''},[]));assert.throws(()=>livePayload(d,[1,2,3,4]));
});
test('disabled Send explains missing/invalid fields and clears when ready',async()=>{
 const {sendBlockReason,validEmail}=await import('../prototype/posting.mjs');
 const d={senderName:'有人',senderEmail:'not-an-email',subject:'Re: test',body:'回覆'};
 assert.match(sendBlockReason(d,{live:true}),/Email 格式唔正確/);
 assert.equal(validEmail('nickname@example.invalid'),true);
 d.senderEmail='nickname@example.invalid';assert.equal(sendBlockReason(d,{live:true}),'');
 assert.match(sendBlockReason({...d,senderName:''},{live:true}),/Name/);
 assert.match(sendBlockReason({...d,senderEmail:''},{live:true}),/Email/);
 assert.match(sendBlockReason({...d,body:''},{live:true}),/正文/);
 assert.match(sendBlockReason({...d,subject:''},{live:true}),/Subject/);
 assert.match(sendBlockReason(d,{attachingImages:true}),/圖片/);
 assert.match(sendBlockReason(d,{sending:true}),/正在發送/);
 assert.equal(sendBlockReason({...d,senderEmail:''},{live:false}),'');
});
test('same-content retry keeps ID; adding/changing photos or body creates a new ID',async()=>{
 const {prepareLivePayload,renewPostId}=await import('../prototype/posting.mjs');
 const d={group:'test.test',subject:'Reply',body:'內容',senderName:'Test',senderEmail:'test@example.invalid',postId:'initial'};
 let sequence=0;const deps={uuid:()=>`new-${++sequence}`,hash:async text=>text};
 assert.equal((await prepareLivePayload(d,[],deps)).postId,'initial');
 assert.equal((await prepareLivePayload(d,[],deps)).postId,'initial');
 const photos=['data:image/png;base64,fixture'];assert.equal((await prepareLivePayload(d,photos,deps)).postId,'new-1');
 assert.equal((await prepareLivePayload(d,photos,deps)).postId,'new-1');
 d.body='新內容';assert.equal((await prepareLivePayload(d,photos,deps)).postId,'new-2');
 d.duplicatePost=true;d.deliveryError='duplicate';const savedBody=d.body;
 renewPostId(d,deps.uuid);assert.equal(d.postId,'new-3');assert.equal(d.body,savedBody);assert.equal(d.deliveryError,undefined);
 assert.equal((await prepareLivePayload(d,photos,deps)).postId,'new-3');
});
