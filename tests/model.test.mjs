import {test} from 'node:test';
import assert from 'node:assert/strict';
import {seed,unread,markThreadRead,filteredThreads,replyDraft,postDraft,validateServer,upgradeHierarchy,messageTree,readingSequence,adjacentMessage,swipeDirection,threadSwipeAction,replyHistory,quotedLines,commitDraft,mergeRepository,MAX_ATTACHMENTS,selectAttachments,restoreAttachmentCache} from '../prototype/model.mjs';
test('逐篇閱讀同整串標已讀，未讀數唔會負數',()=>{const t=seed().threads.find(t=>t.messages.length===9);const before=unread(t);t.messages[0].read=true;assert.equal(unread(t),before-1);t.messages[0].read=true;assert.equal(unread(t),before-1);markThreadRead(t);assert.equal(unread(t),0)});
test('篩選限於目前 server／group；支援正文搜尋同收藏',()=>{const s=seed();const t=s.threads.find(t=>t.group==='general.chat'&&t.star);assert.deepEqual(filteredThreads(s,'s1','general.chat',{favouritesOnly:true}),[t]);assert.ok(filteredThreads(s,'s1','general.chat',{query:'慢慢坐'}).length);assert.equal(filteredThreads(s,'other','general.chat').length,0);s.threads.filter(t=>t.group==='general.chat').forEach(markThreadRead);assert.equal(filteredThreads(s,'s1','general.chat',{unreadOnly:true}).length,0)});
test('回覆保留父串、引文，模擬發佈唔產生新串',()=>{const s=seed(),t=s.threads.find(t=>t.group==='general.chat'&&t.messages.length===9);const draft=replyDraft(t,t.messages[0]);assert.equal(draft.parent,t.id);assert.ok(draft.body.includes('> 以前'));const n=s.threads.length,m=t.messages.length;draft.body='同意。'+draft.body;postDraft(s,draft);assert.equal(s.threads.length,n);assert.equal(t.messages.length,m+1);assert.equal(t.messages.at(-1).read,false);assert.equal(filteredThreads(s,'s1','general.chat',{latest:true})[0].id,t.id)});
test('新文章出現喺正確群組，空內容唔可以發佈',()=>{const s=seed();const d={server:'s1',group:'game.ps4',subject:'測試',body:'內容'};const t=postDraft(s,d);assert.equal(filteredThreads(s,'s1','game.ps4')[0],t);assert.throws(()=>postDraft(s,{...d,body:' '}));assert.equal(s.draft,null)});
test('設定驗證 port 範圍同文章保留上限',()=>{const s=seed().servers[0];assert.equal(validateServer(s),'');assert.ok(validateServer({...s,port:65536}));assert.ok(validateServer({...s,host:''}));assert.ok(validateServer({...s,keep:1}));assert.ok(validateServer({...s,port:119.5}))});
test('父子關係呈現多層分支，兄弟回覆唔會誤當成子回覆',()=>{
 const t={id:'tree',messages:[{id:'root'},{id:'a',parentId:'root'},{id:'b',parentId:'root'},{id:'a1',parentId:'a'},{id:'a11',parentId:'a1'},{id:'b1',parentId:'b'}]};
 assert.deepEqual(messageTree(t).map(e=>[e.message.id,e.depth]),[['root',0],['a',1],['a1',2],['a11',3],['b',1],['b1',2]]);
 assert.deepEqual(messageTree(t).map(e=>e.index),[0,1,3,4,2,5]);
});
test('回覆指定 message 成為其子節點，重載後層級保持',()=>{
 const s=seed(),t=s.threads.find(t=>t.messages.length===9),parent=t.messages[3];
 const d=replyDraft(t,parent);assert.equal(d.replyTo,parent.id);postDraft(s,d);
 const child=t.messages.at(-1);assert.equal(child.parentId,parent.id);
 const tree=messageTree(t),i=tree.findIndex(e=>e.message.id===parent.id);
 assert.equal(tree[i+1].message.id,child.id);assert.equal(tree[i+1].depth,tree[i].depth+1);
 assert.deepEqual(messageTree(upgradeHierarchy(JSON.parse(JSON.stringify(s))).threads.find(x=>x.id===t.id)),tree);
});
test('下一篇跨串到第一篇，上一篇跨串到最後一篇，兩端停止',()=>{
 const ts=[{id:'one',messages:[{id:'a'},{id:'b',parentId:'a'}]},{id:'two',messages:[{id:'c'}]}];
 const route=readingSequence(ts);
 assert.equal(adjacentMessage(route,'one','a',1).messageId,'b');
 assert.deepEqual(adjacentMessage(route,'one','b',1),{threadId:'two',messageId:'c',index:0,depth:0});
 assert.equal(adjacentMessage(route,'two','c',-1).messageId,'b');
 assert.equal(adjacentMessage(route,'one','a',-1),null);
 assert.equal(adjacentMessage(route,'two','c',1),null);
});
test('跨串使用畫面順序；閱讀清空未讀唔會跳串；唔走出目前篩選範圍',()=>{
 const s=seed(),visible=filteredThreads(s,'s1','general.chat',{unreadOnly:true,latest:true}),route=readingSequence(visible);
 const first=visible[0],last=messageTree(first).at(-1).message;
 markThreadRead(first);
 assert.equal(filteredThreads(s,'s1','general.chat',{unreadOnly:true}).some(t=>t.id===first.id),false);
 assert.equal(adjacentMessage(route,first.id,last.id,1).threadId,visible[1].id);
 assert.ok(route.every(e=>visible.some(t=>t.id===e.threadId)));
});
test('舊版資料升級保留已讀、草稿同自訂關係；唔虛構舊回覆嘅父節點',()=>{
 const s=seed(),t=s.threads.find(t=>t.messages.length===9);
 const oldDraft={subject:'保留草稿'};s.draft=oldDraft;
 t.messages.forEach(m=>delete m.parentId);t.messages.push({id:'legacy-reply',read:true});
 upgradeHierarchy(s);assert.equal(t.messages[3].parentId,t.messages[2].id);assert.equal(t.messages.at(-1).parentId,t.messages[0].id);
 assert.equal(t.messages.at(-1).read,true);assert.equal(s.draft,oldDraft);
 t.messages[3].parentId=t.messages[0].id;upgradeHierarchy(s);assert.equal(t.messages[3].parentId,t.messages[0].id);
});
test('缺失父節點及循環引用唔會隱藏文章或無限循環',()=>{
 const t={messages:[{id:'a',parentId:'b'},{id:'b',parentId:'a'},{id:'c',parentId:'gone'},{id:'d',parentId:'d'}]};
 const tree=messageTree(t);assert.equal(tree.length,4);assert.equal(new Set(tree.map(e=>e.message.id)).size,4);
});
test('左 swipe 向前、右 swipe 向後；垂直捲動同輕觸唔切篇',()=>{
 assert.equal(swipeDirection({x:300,y:200},{x:100,y:205}),1);
 assert.equal(swipeDirection({x:100,y:200},{x:300,y:205}),-1);
 assert.equal(swipeDirection({x:300,y:200},{x:250,y:205}),0);
 assert.equal(swipeDirection({x:300,y:200},{x:180,y:400}),0);
});
test('列表右 swipe 只展開、左 swipe 只收起，重複方向唔會 toggle',()=>{
 const left={x:100,y:200},right={x:300,y:205};
 assert.equal(threadSwipeAction(left,right,false),'expand');
 assert.equal(threadSwipeAction(left,right,true),null);
 assert.equal(threadSwipeAction(right,left,true),'collapse');
 assert.equal(threadSwipeAction(right,left,false),null);
 assert.equal(threadSwipeAction(left,{x:110,y:400},true),null);
 assert.equal(threadSwipeAction(left,{x:140,y:205},false),null);
});
function historyFixture(){
 const make=(id,parentId)=>({id,parentId,author:'Author '+id,time:'18:00',body:id+' ONLY'});
 return {id:'history',server:'s1',group:'general.chat',subject:'分支測試',messages:[make('A',null),make('B','A'),make('X','A'),make('C','B'),make('Y','X'),make('D','C'),make('E','D')]};
}
test('引用沿四代父節點 E D C B，唔包含時間相鄰嘅其他分支或第五代',()=>{
 const t=historyFixture(),d=replyDraft(t,t.messages.at(-1));
 assert.deepEqual(d.quoteMessageIds,['E','D','C','B']);
 for(const id of ['E','D','C','B'])assert.ok(d.body.includes(id+' ONLY'));
 for(const id of ['A','X','Y'])assert.equal(d.body.includes(id+' ONLY'),false);
 const content=quotedLines(d.body).filter(l=>l.text.endsWith(' ONLY'));
 assert.deepEqual(content.map(l=>[l.text,l.depth]),[['E ONLY',1],['D ONLY',2],['C ONLY',3],['B ONLY',4]]);
});
test('已有 quote 唔會重複夾入或帶入更舊歷史，發佈後再回覆仍只限四代',()=>{
 const s=seed(),t=historyFixture();s.threads.push(t);
 t.messages.at(-1).body+='\n\nOn 17:00 04/11, old wrote:\n> A ONLY\n>> X ONLY';
 t.messages.at(-1).quote='Y ONLY';
 const d=replyDraft(t,t.messages.at(-1));d.body='F ONLY'+d.body;
 postDraft(s,d);
 const f=t.messages.at(-1);assert.equal(f.ownBody,'F ONLY');
 const next=replyDraft(t,f);
 assert.deepEqual(next.quoteMessageIds,[f.id,'E','D','C']);
 for(const id of ['A','B','X','Y'])assert.equal(next.body.includes(id+' ONLY'),false);
 for(const id of ['F','E','D','C'])assert.equal(next.body.split(id+' ONLY').length-1,1);
 assert.equal(Math.max(...quotedLines(next.body).map(l=>l.depth)),4);
});
test('不足四代引用已有祖先；缺失父節點或循環時安全停止',()=>{
 const t=historyFixture();
 assert.deepEqual(replyHistory(t,'A').map(m=>m.id),['A']);
 assert.deepEqual(replyHistory(t,'C').map(m=>m.id),['C','B','A']);
 t.messages[1].parentId='missing';assert.deepEqual(replyHistory(t,'C').map(m=>m.id),['C','B']);
 t.messages[1].parentId='C';assert.deepEqual(replyHistory(t,'C').map(m=>m.id),['C','B']);
 assert.deepEqual(replyHistory(t,'missing'),[]);
});
test('Send 成功寫入後重讀仍只得一篇新回覆，保留父子關係同四代引文',()=>{
 const original=seed(),thread=original.threads.find(t=>t.messages.length===9),parent=thread.messages[3];
 const draft=replyDraft(thread,parent);draft.body='新回覆驗證'+draft.body;original.draft=draft;
 let stored;
 const result=commitDraft(original,draft,[],candidate=>{stored=JSON.stringify(candidate);return true});
 assert.equal(thread.messages.length,9); // Caller only adopts a successful commit.
 assert.equal(result.thread.messages.length,10);
 assert.equal(result.state.draft,null);
 const reload=JSON.parse(stored),saved=reload.threads.find(t=>t.id===thread.id);
 assert.equal(saved.messages.filter(m=>m.id===result.message.id).length,1);
 assert.equal(saved.messages.at(-1).parentId,parent.id);
 assert.equal(saved.messages.at(-1).ownBody,'新回覆驗證');
 assert.equal(Math.max(...quotedLines(saved.messages.at(-1).body).map(l=>l.depth)),4);
 assert.equal(JSON.parse(JSON.stringify(reload)).threads.find(t=>t.id===thread.id).messages.length,10);
});
test('儲存失敗保留草稿及原串，重試 Send 唔會重複加入回覆',()=>{
 const original=seed(),t=original.threads.find(t=>t.messages.length===9),d=replyDraft(t,t.messages[3]);original.draft=d;
 assert.throws(()=>commitDraft(original,d,[],()=>false),/草稿已保留/);
 assert.equal(t.messages.length,9);assert.equal(original.draft,d);
 const result=commitDraft(original,d,[],()=>true);
 assert.equal(result.thread.messages.length,10);assert.equal(result.state.draft,null);
 const missing={...d,parent:'deleted-thread'};
 assert.throws(()=>commitDraft(original,missing,[],()=>true),/討論串已不存在/);
 assert.equal(original.draft,d);
});
test('Send 只更新 repository；刷新先見自己同其他人新回覆，兩篇都係未讀',()=>{
 const visible=seed(),thread=visible.threads.find(t=>t.messages.length===9),parent=thread.messages[3];
 markThreadRead(thread);
 let repository=JSON.parse(JSON.stringify(visible));
 const persist=candidate=>{repository=JSON.parse(JSON.stringify(mergeRepository(candidate,repository)));return true};
 const result=commitDraft(visible,replyDraft(thread,parent),[],persist);
 assert.equal(thread.messages.length,9);assert.equal(unread(thread),0);
 assert.equal(repository.threads.find(t=>t.id===thread.id).messages.length,10);
 // Opening an old article or saving another draft before Refresh must not
 // erase or mark the unseen own reply read.
 thread.messages[0].read=true;persist(visible);
 const remoteThread=repository.threads.find(t=>t.id===thread.id);
 assert.equal(remoteThread.messages.find(m=>m.id===result.message.id).read,false);
 const otherDraft=replyDraft(remoteThread,remoteThread.messages[1]);otherDraft.body='其他人新回覆'+otherDraft.body;
 postDraft(repository,otherDraft);
 assert.equal(thread.messages.length,9);
 const refreshed=JSON.parse(JSON.stringify(repository)).threads.find(t=>t.id===thread.id);
 assert.equal(refreshed.messages.length,11);assert.equal(unread(refreshed),2);
 assert.equal(refreshed.messages.find(m=>m.id===result.message.id).parentId,parent.id);
 assert.equal(new Set(refreshed.messages.map(m=>m.id)).size,11);
});
test('未刷新前連續發送會保留兩篇新回覆，但舊列表數量同次序不變',()=>{
 const visible=seed(),t=visible.threads.find(t=>t.messages.length===9),oldIds=t.messages.map(m=>m.id);
 let repository=JSON.parse(JSON.stringify(visible));
 const persist=candidate=>{repository=mergeRepository(candidate,repository);return true};
 const a=commitDraft(visible,replyDraft(t,t.messages[3]),[],persist);
 const b=commitDraft(visible,replyDraft(t,t.messages[3]),[],persist);
 assert.deepEqual(t.messages.map(m=>m.id),oldIds);
 const refreshed=repository.threads.find(x=>x.id===t.id);
 assert.deepEqual(refreshed.messages.slice(-2).map(m=>m.id),[a.message.id,b.message.id]);
 assert.ok(refreshed.messages.slice(-2).every(m=>m.read===false));
});
test('相片上限三張：批量超額只加入剩餘位置，移除後可補一張',()=>{
 assert.equal(MAX_ATTACHMENTS,3);
 assert.deepEqual(selectAttachments(0,['a','b','c','d']),{accepted:['a','b','c'],rejected:1});
 assert.deepEqual(selectAttachments(2,['a','b','c']),{accepted:['a'],rejected:2});
 assert.deepEqual(selectAttachments(3,['d']),{accepted:[],rejected:1});
 assert.deepEqual(selectAttachments(2,['d']),{accepted:['d'],rejected:0});
});
test('Send 同樣阻止四張附件，保留草稿；三張可正常掛喺父文章下面',()=>{
 const s=seed(),t=s.threads.find(t=>t.messages.length===9),d=replyDraft(t,t.messages[3]);s.draft=d;
 let writes=0;
 assert.throws(()=>commitDraft(s,d,['a','b','c','d'],()=>{writes++;return true}),/最多只可以加 3 張相/);
 assert.equal(writes,0);assert.equal(s.draft,d);assert.equal(t.messages.length,9);
 const result=commitDraft(s,d,['a','b','c'],()=>true);
 assert.deepEqual(result.message.images,['a','b','c']);assert.equal(result.message.parentId,t.messages[3].id);
 assert.equal(result.message.read,false);
});
test('Refresh 混合本機圖片同示範圖時保留完整三張相片及原有順序',()=>{
 const s={threads:[{messages:[{id:'mixed',images:['demo']},{id:'other',images:['server-image']}]}]};
 const original=['file-a','file-b','demo'],cache=new Map([['mixed',original]]);
 restoreAttachmentCache(s,cache);
 assert.deepEqual(s.threads[0].messages[0].images,original);
 assert.notEqual(s.threads[0].messages[0].images,original);
 assert.deepEqual(s.threads[0].messages[1].images,['server-image']);
});
