import {downloadInventory,chooseNumbers,batches} from './downloads.mjs';
import {articleSections} from './message-layout.mjs';
import {validEmail,sendBlockReason,prepareLivePayload,renewPostId,prepareLiveReply,postLive} from './posting.mjs?v=20261105-layout';
import {openExternalLink} from './links.mjs?v=20261105-links3';
import {bindArticleGestures} from './gestures.mjs?v=20261105-links3';
import {nntp,mergeHeaders,withoutSupersededThreads,needsArticleContent,applyArticleContent,serverEndpoint,headersBatch} from './nntp.mjs?v=20261105-servers';
import {readMigratedStorage} from './storage.mjs';
import {renderMediaLinks,mountEmbeds} from './embeds.mjs?v=20261105-fbshare';
import {groups,sampleImage,seed,unread,markThreadRead,filteredThreads,replyDraft,validateServer,upgradeHierarchy,messageTree,readingSequence,adjacentMessage,swipeDirection,threadSwipeAction,quotedLines,commitDraft,mergeRepository,MAX_ATTACHMENTS,selectAttachments,restoreAttachmentCache} from './model.mjs';
const app=document.getElementById('app'),sheet=document.getElementById('sheet'),toastEl=document.getElementById('toast');
const key='yrnewsex-prototype-v1',postContextKey='yrnewsex-post-context-v1';
// Compatibility with saved data from before the yrNewsEx rename.
const legacyKey='yrnews-prototype-v1',legacyPostContextKey='yrnews-post-context-v1';
const storedData=()=>readMigratedStorage(localStorage,key,legacyKey);
let state;
try{state=JSON.parse(storedData());if(state?.version!==1||!Array.isArray(state.servers)||!Array.isArray(state.threads))state=seed()}catch{state=seed()}
upgradeHierarchy(state);
let readingThreadIds=[],readingRoute=[],suppressArticleLinkClickUntil=0,disposeEmbeds=null;
const stagedImages=new Map();
let catalog=[],subscriptionSelection=new Set(),subscriptionQuery='',liveRefreshToken=0;
let view='groups',serverId=state.servers[0]?.id,group='general.chat',threadId=null,messageIndex=0,expanded=new Set(),query='',unreadOnly=false,favouritesOnly=false,latest=false,editing=false,composeReturn='list',draftImages=[],oldPages=new Set(),toastTimer,refreshing=false,listScroll=0,selectedMessageId=null,sending=false,attachingImages=false;
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const paths={back:'m15 4-8 8 8 8',next:'m9 4 8 8-8 8',up:'m5 15 7-7 7 7',down:'m5 9 7 7 7-7',refresh:'M20 9a8 8 0 1 0 0 7 M20 3v6h-6',plus:'M12 4v16M4 12h16',compose:'M13 5H5v15h15v-8 M10 14l1-4 8-8 3 3-8 8-4 1',action:'M8 8H4v13h16V8h-4 M12 16V2m-4 4 4-4 4 4',reply:'M9 5 2 11l7 6v-4c6 0 10 1 13 6-1-8-5-11-13-11V5',search:'M10 17a7 7 0 1 0 0-14 7 7 0 0 0 0 14m5-2 6 6',camera:'M4 7H1v14h22V7h-6l-2-4H9L7 7H4 M17 14a5 5 0 1 0-10 0 5 5 0 0 0 10 0',info:'M12 10v7m0-11v.2 M22 12a10 10 0 1 0-20 0 10 10 0 0 0 20 0',star:'m12 2 3 6.5 7 1-5 5 1.2 7-6.2-3.4L5.8 22 7 14.5l-5-5 7-1Z'};
const icon=name=>`<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name]||paths.action}"/></svg>`;
const btn=(label,action,content=esc(label),extra='')=>`<button type="button" aria-label="${esc(label)}" data-action="${action}" ${extra}>${content}</button>`;
const chevron=`<span class="chevron">${icon('next')}</span>`;
function save(snapshot=state){try{const stored=JSON.parse(storedData());const repository=mergeRepository(snapshot,withoutSupersededThreads(snapshot,stored));localStorage.setItem(key,JSON.stringify(repository,(k,v)=>k==='images'?v.filter(src=>src===sampleImage):v));return true}catch{toast('未能儲存本機變更，請再試。');return false}}
function toast(text){clearTimeout(toastTimer);toastEl.textContent=text;toastEl.classList.add('visible');toastTimer=setTimeout(()=>toastEl.classList.remove('visible'),3200)}
function currentServer(){return state.servers.find(s=>s.id===serverId)}
function currentThread(){return state.threads.find(t=>t.id===threadId)}
function list(){return filteredThreads(state,serverId,group,{query,unreadOnly,favouritesOnly,latest})}
function nav(left,center='',right=''){return `<header class="nav">${left||'<span class="spacer"></span>'}<strong>${esc(center)}</strong><div class="right">${right}</div></header>`}
function clearPostContext(){selectedMessageId=null;try{sessionStorage.removeItem(postContextKey);sessionStorage.removeItem(legacyPostContextKey)}catch{}}
function showGroups(){cancelLiveRefresh();articleRequest++;clearPostContext();view='groups';editing=false;render()}
function openGroup(name,sid=serverId){cancelLiveRefresh();articleRequest++;clearPostContext();serverId=sid;group=name;view='list';query='';listScroll=0;expanded.clear();unreadOnly=false;favouritesOnly=false;render();if(currentServer()?.mode==='nntp')refresh()}
function readingThreads(){const byId=new Map(state.threads.map(t=>[t.id,t]));return readingThreadIds.map(id=>byId.get(id)).filter(Boolean)}
function neighbor(direction){const t=currentThread();return adjacentMessage(readingRoute,t.id,t.messages[messageIndex].id,direction)}
function moveMessage(direction){const target=neighbor(direction);if(target)openArticle(target.threadId,target.index,direction)}
let articleRequest=0;
async function openArticle(id,index=0,direction=1){
 cancelLiveRefresh();
 const request=++articleRequest,sourceView=view;
 const target=state.threads.find(t=>t.id===id)?.messages[index];
 if(currentServer()?.mode==='nntp'&&target&&needsArticleContent(target)){
  toast('正在讀取文章…');
  try{const result=await news('article',{group,number:target.number});if(request!==articleRequest||view!==sourceView)return;if(result.id!==target.id)throw new Error('文章編號已改變，請 Refresh');
   // A concurrent header refresh can replace message objects during the fetch.
   // Apply bytes to the current cache by identity, not the detached old object.
   const activeThread=state.threads.find(t=>t.server===serverId&&t.group===group&&t.messages.some(m=>m.id===result.id));
   if(!activeThread)return;
   id=activeThread.id;index=activeThread.messages.findIndex(m=>m.id===result.id);
   applyArticleContent(activeThread.messages[index],result)}
  catch(e){toast(e.message);return}
 }

 if(view==='list'){
  listScroll=document.getElementById('thread-list').scrollTop;
  // Freeze the visible thread order before marking anything read. In Unread
  // Only, finishing this thread must not remove it from the reading route.
  const visible=list();readingThreadIds=visible.map(t=>t.id);readingRoute=readingSequence(visible);
 }
 threadId=id;const t=currentThread();
 messageIndex=Math.max(0,Math.min(index,t.messages.length-1));
 t.messages[messageIndex].read=true;expanded.add(id);save();view='article';render();
 app.querySelector('.screen').classList.toggle('reading-back',direction<0);
 if(currentServer()?.mode==='nntp')toast('文章已載入 · Live');
}
function groupScreen(){return nav(btn(editing?'完成':'編輯','edit'),'',btn('Add Server','add-server',icon('plus')))+`<h1 class="large-title">Groups</h1><div class="scroll">${state.servers.map(s=>`<section>${btn('設定 '+s.host,'settings',`${esc(s.host)}${s.mode==='nntp'?'':' · Demo'}${chevron}`,`class="server-row" data-server="${esc(s.id)}"`)}${s.subscriptions.map(g=>`<div class="group-row">${btn(g,'group',esc(g),`style="color:white;text-align:left;flex:1;min-height:48px;padding:0;overflow-wrap:anywhere" data-server="${esc(s.id)}" data-group="${esc(g)}"`)}${editing?btn('取消訂閱 '+g,'unsubscribe','⊖',`class="danger" data-server="${esc(s.id)}" data-group="${esc(g)}"`):chevron}</div>`).join('')}</section>`).join('')||'<p class="empty">No Servers<br>Tap + to add a server.</p>'}</div><footer class="toolbar"><span style="width:44px"></span><span class="info brand">yrNewsEx</span>${btn('About prototype','about',icon('info'))}</footer>`}
function replyRows(thread){
 const byId=new Map(thread.messages.map(m=>[m.id,m]));
 return messageTree(thread).filter(entry=>entry.index!==0).map(({message:m,index,depth})=>{
  const parent=byId.get(m.parentId);
  return `<div data-thread="${esc(thread.id)}" class="thread-row reply-row ${m.read?'read':''} ${m.id===selectedMessageId?'selected':''}" data-depth="${depth}" data-message="${esc(m.id)}" data-parent="${esc(m.parentId||'')}" style="--depth:${Math.min(depth,7)}">${btn('Re: '+thread.subject+' '+(index+1),'article',`<span class="subject">Re: ${esc(thread.subject)}</span><span class="meta">${esc(m.author)} | ${esc(m.time)} | 1KB</span>`,`class="thread-main" data-thread="${esc(thread.id)}" data-index="${index}" title="${esc('第 '+depth+' 層回覆 · 回覆 '+(parent?.author||'原文'))}"`)}${chevron}</div>`;
 }).join('');
}
function threadRows(){return list().map(t=>`<div data-thread="${esc(t.id)}" data-message="${esc(t.messages[0].id)}" class="thread-row ${t.messages[0].id===selectedMessageId?'selected':''} ${unread(t)?'':'read'} ${t.star?'starred':''}">${btn(t.subject,'article',`<span class="subject">${esc(t.subject)}</span><span class="meta">${esc(t.messages[0].author)} | ${esc(t.messages[0].time)} | ${t.messages[0].bytes?Math.max(1,Math.round(t.messages[0].bytes/1024)):t.messages[0].images.length?'185':'1'}KB</span>`,`class="thread-main" data-thread="${esc(t.id)}"`)}${t.messages.length>1?btn('展開 '+t.subject,'expand',`<span class="count ${unread(t)?'':'zero'}">${unread(t)}/${t.messages.length}</span>`,`class="count-wrap" aria-expanded="${expanded.has(t.id)}" data-thread="${esc(t.id)}"`):chevron}</div>${expanded.has(t.id)?replyRows(t):''}`).join('')||`<p class="empty">${query?'No Results':unreadOnly?'No Unread Messages':favouritesOnly?'No Favourites':'No Messages'}<br>${query?'試下另一個關鍵字。':'從右下角選單切換顯示範圍。'}</p>`}
function setThreadExpanded(id,open){
 const thread=state.threads.find(t=>t.id===id);
 if(!thread||thread.messages.length<2||expanded.has(id)===open)return;
 const scroll=document.getElementById('thread-list');
 const root=[...scroll.querySelectorAll('.thread-row:not(.reply-row)')].find(row=>row.dataset.thread===id);
 const anchor=root?Math.max(0,root.getBoundingClientRect().top-scroll.getBoundingClientRect().top):0;
 const position=scroll.scrollTop;
 open?expanded.add(id):expanded.delete(id);
 scroll.innerHTML=threadRows();scroll.scrollTop=position;
 // Collapsing from a deep reply keeps the thread root in view, instead of
 // leaving the reader at an unrelated thread below the removed replies.
 if(!open){
  const updated=[...scroll.querySelectorAll('.thread-row:not(.reply-row)')].find(row=>row.dataset.thread===id);
  if(updated)scroll.scrollTop+=updated.getBoundingClientRect().top-scroll.getBoundingClientRect().top-anchor;
 }
 listScroll=scroll.scrollTop;
}
function listScreen(){return nav(btn('Groups','groups',icon('back')+'Groups','class="back"'),'',btn('Refresh','refresh',icon('refresh'),refreshing?'class="loading" disabled':''))+`<h1 class="large-title">${esc(group)}</h1><div class="search">${icon('search')}<input type="search" id="search" aria-label="搜尋文章" placeholder="搜尋" value="${esc(query)}" autocomplete="off"></div>${unreadOnly||favouritesOnly||latest?`<div class="filter-label">${[unreadOnly?'Unread Only':'',favouritesOnly?'Favourites Only':'',latest?'Latest Reply':''].filter(Boolean).join(' · ')}</div>`:''}<div class="scroll" id="thread-list">${threadRows()}</div><footer class="toolbar">${btn('New Message','compose',icon('compose'))}<span class="info" id="unread-total">${groupUnread()} Unread Messages</span>${btn('Group Actions','group-actions',icon('action'))}</footer>`}
function groupUnread(){return state.threads.filter(t=>t.server===serverId&&t.group===group).reduce((n,t)=>n+unread(t),0)}
function articleText(text,seen=new Set()){
 let html='',depth=0;
 for(const line of quotedLines(text)){
  while(depth<line.depth){html+='<blockquote>';depth++}
  while(depth>line.depth){html+='</blockquote>';depth--}
  html+=renderMediaLinks(line.text,seen)+'\n';
 }
 return html+'</blockquote>'.repeat(depth);
}
function articleContent(message,seen){
 return articleSections(message).map(part=>part.type==='image'?`<img src="${esc(message.images[part.index])}" alt="文章圖片" loading="lazy" decoding="async">`:articleText(part.text,seen)).join('');
}
function articleScreen(){const t=currentThread(),m=t.messages[messageIndex];const all=readingThreads(),position=all.findIndex(x=>x.id===t.id),ordinal=messageTree(t).findIndex(e=>e.index===messageIndex),seen=new Set();return nav(btn(group,'back-list',icon('back')+esc(group),'class="back"'),`${ordinal+1} of ${t.messages.length}`,btn('Refresh','refresh',icon('refresh')))+`<div class="scroll" id="article-scroll"><header class="article-head"><h2>${messageIndex?'Re: ':''}${esc(t.subject)}</h2><div class="article-author">${esc(m.author)} &lt;${esc(m.email)}&gt;</div><div class="article-date">${m.createdAt?esc(new Date(m.createdAt).toLocaleString('zh-HK')):`4 11月 2026, ${esc(m.time)} 下午`}</div></header><article class="article-body">${articleContent(m,seen)}${m.quote?`<br><br>On 16:39 04/11, somebody wrote:<blockquote>${renderMediaLinks(m.quote,seen)}</blockquote>`:''}${(m.imageWarnings||[]).map(w=>`<p class="image-warning">${esc(w)}</p>`).join('')}${currentServer()?.mode==='nntp'?'':'<div class="signature">--<br>示例讀者</div>'}</article></div><footer class="toolbar">${btn('Reply','reply',icon('reply'))}${btn('Previous Message','prev-message',icon('back'),!neighbor(-1)?'disabled':'')}${btn('Next Message','next-message',icon('next'),!neighbor(1)?'disabled':'')}${btn('Previous Thread','prev-thread',icon('up'),position<=0?'disabled':'')}${btn('Next Thread','next-thread',icon('down'),position<0||position>=all.length-1?'disabled':'')}${btn('Article Actions','article-actions',icon('action'))}</footer>`}
function render(){disposeEmbeds?.();disposeEmbeds=null;app.innerHTML=`<section class="screen ${['settings','subscriptions'].includes(view)?'form-screen':view==='compose'?'composer':''}">${view==='groups'?groupScreen():view==='list'?listScreen():view==='article'?articleScreen():view==='settings'?settingsScreen():view==='subscriptions'?subscriptionScreen():composeScreen()}</section>`;wireScreen();if(view==='list')document.getElementById('thread-list').scrollTop=listScroll;if(view==='article')disposeEmbeds=mountEmbeds(app.querySelector('.article-body'))}
function actions(items,title=''){sheet.innerHTML=`<div class="sheet-group">${title?`<div class="sheet-title">${esc(title)}</div>`:''}${items.map(([label,act,extra])=>btn(label,act,esc(label),extra||'')).join('')}</div><div class="sheet-group">${btn('Cancel','close-sheet','Cancel','class="cancel"')}</div>`;sheet.showModal()}
function closeSheet(){sheet.close()}
function startCompose(reply=false){
 if(currentServer()?.mode==='nntp'&&(!validEmail(currentServer().email||'')||!currentServer().name?.trim())){settings(serverId);toast('請先喺 server 設定 Name 同 Email。');return}
 if(state.draft){actions([['繼續上次草稿','resume-draft'],['開新草稿（取代舊草稿）',reply?'replace-reply':'replace-draft']],'Saved Draft');return}
 createDraft(reply);
}
let preparingReply=false;
async function createDraft(reply){
 if(preparingReply)return;
 const server=currentServer(),sourceView=view,sid=serverId,sourceThread=currentThread(),sourceMessageId=sourceThread?.messages[messageIndex]?.id;
 composeReturn=view;
 try{
  preparingReply=true;
  let draft;
  if(reply&&server.mode==='nntp'){
   toast('正在載入父訊息引用…');
   draft=await prepareLiveReply(sourceThread,sourceThread.messages[messageIndex],id=>news('article',{group,id,images:0}));
   if(view!==sourceView||serverId!==sid||(currentThread()?.id!==sourceThread.id||currentThread()?.messages[messageIndex]?.id!==sourceMessageId))return;
  }else draft=reply?replyDraft(currentThread(),currentThread().messages[messageIndex]):{server:serverId,group,parent:null,subject:'',body:'',images:[]};
  Object.assign(draft,{senderName:server.name||'',senderEmail:server.email||'',encoding:server.encoding||'utf-8',...serverEndpoint(server),postId:crypto.randomUUID()});
  state.draft=draft;draftImages=[];view='compose';save();render();
 }catch(e){toast('未能載入引用：'+e.message)}finally{preparingReply=false}
}
function liveDraft(){return state.servers.find(s=>s.id===state.draft?.server)?.mode==='nntp'}
function syncDraftProfile(){
 const server=state.servers.find(s=>s.id===state.draft?.server);
 if(server?.mode==='nntp')Object.assign(state.draft,{senderName:server.name||'',senderEmail:server.email||'',encoding:server.encoding||'utf-8',...serverEndpoint(server)});
}
function blockedSendReason(){syncDraftProfile();const reason=sendBlockReason(state.draft,{live:liveDraft(),attachingImages,sending});return liveDraft()&&/Name|Email/.test(reason)?'請先喺 server 設定 Name 同有效 Email。':reason}

function canSend(){return !blockedSendReason()}
function updateSendStatus(){
 app.querySelector('[data-action="send"]').disabled=!canSend();
 document.getElementById('compose-send-help').textContent=blockedSendReason();
 const email=document.getElementById('senderEmail');
 if(email)email.setAttribute('aria-invalid',String(!!email.value.trim()&&!validEmail(email.value)));
}

function composeScreen(){const d=state.draft;return nav(btn('取消','cancel-compose'),' ',btn('Attach Photo','photo',icon('camera'),draftImages.length>=MAX_ATTACHMENTS||attachingImages?'disabled':'')+btn('Send','send','Send',!canSend()?'disabled':''))+`<div class="compose-field"><label>Group:</label><span>${esc(d.group)}</span></div><div class="compose-field"><label for="subject">Subject:</label><input id="subject" aria-label="Subject" value="${esc(d.subject)}" autocomplete="off"></div><p id="compose-send-help" class="compose-help" role="status" aria-live="polite">${esc(blockedSendReason())}</p>${d.deliveryError?`<div class="delivery-error" role="status">${esc(d.deliveryError)}${d.duplicatePost?btn('用新識別碼再試','renew-post-id','用新識別碼再試'):''}</div>`:''}<textarea id="body" class="compose-body" aria-label="正文" placeholder="">${esc(d.body)}</textarea><div class="attachments">${draftImages.map((src,i)=>`<div class="attachment"><img src="${esc(src)}" alt="附件 ${i+1}">${btn('移除附件 '+(i+1),'remove-image','×',`data-index="${i}" ${attachingImages?'disabled':''}`)}</div>`).join('')}</div><div class="compose-foot"><span class="attachment-status" aria-live="polite">Photos: ${draftImages.length}/${MAX_ATTACHMENTS}${attachingImages?' · Loading…':''}</span><br>--<br>${liveDraft()?'yrNewsEx · Live<br>Send 會公開發佈到 '+esc(currentServer().host):'yrNewsEx · demo'}</div><input type="file" id="photo-input" accept="image/png,image/jpeg,image/webp,image/gif" multiple><input type="file" id="camera-input" accept="image/*" capture="environment">`}
let settingsDraft=null,settingsReturn='groups';
function settingsScreen(){
 const s=settingsDraft,locked=!!s.id&&s.mode==='nntp';
 return nav(btn('取消','cancel-settings'),'',btn('完成','save-server','完成',settingsValid()?'':'disabled'))+`<h1 class="large-title">${esc(s.id?s.host:'Add Server')}</h1><div class="scroll">${s.id?btn('Subscribe Group','subscribe','Subscribe Group','class="subscribe"'):''}<form id="server-form" class="form-table">${[['host','Server','Enter Server','text'],['port','Port','Empty for Default','number'],['name','Name','Enter Name','text'],['email','Email','Enter Email','email']].map(([id,label,ph,type])=>`<div class="field"><label for="${id}">${label}</label><input id="${id}" name="${id}" type="${type}" value="${esc(s[id])}" placeholder="${ph}" ${id==='port'?'min="1" max="65535"':''} ${locked&&['host','port'].includes(id)?'readonly':''}></div>`).join('')}<div class="field"><label>Login Name</label><input disabled placeholder="Optional"></div><div class="field"><label>Password</label><input disabled placeholder="Optional" type="password"></div><div class="field"><label for="encoding">Encoding</label><select name="encoding" id="encoding"><option value="utf-8" ${s.encoding==='utf-8'?'selected':''}>Unicode (UTF-8)</option><option value="big5" ${s.encoding==='big5'?'selected':''}>Chinese Traditional (Big5)</option></select></div><div class="form-section">Articles:</div><div class="field"><label for="headers">Max headers per refresh</label><input id="headers" name="headers" type="number" min="1" value="${s.headers}"></div><div class="field"><label for="keep">Max articles per group</label><input id="keep" name="keep" type="number" min="1" value="${s.keep}"></div></form>${s.id?btn('Delete Server','delete-server','Delete Server','class="danger delete"'):''}<p class="form-help">Name 同 Email 會用於呢個 server 嘅發文及回覆。${s.mode==='nntp'?'目前支援公開 NNTP；需要登入嘅 server 暫未接通。':''}</p><p id="form-error" class="form-help danger" role="alert"></p></div>`;
}
function settingsIssue(){const s=settingsDraft;return validateServer({...s,port:Number(s.port||119)})||(!s.name?.trim()?'請填寫 Name。':!validEmail(s.email||'')?'Email 格式例如 nickname@example.invalid。':'')}
function settingsValid(){return !settingsIssue()}
function captureSettings(){const f=new FormData(document.getElementById('server-form'));Object.assign(settingsDraft,Object.fromEntries(f));settingsDraft.host=settingsDraft.host.trim();settingsDraft.port=Number(f.get('port')||119);settingsDraft.headers=Number(f.get('headers'));settingsDraft.keep=Number(f.get('keep'));settingsDraft.tls=settingsDraft.port===563}
function settings(sid){cancelLiveRefresh();settingsReturn=view;settingsDraft=sid?structuredClone(state.servers.find(s=>s.id===sid)):{id:null,mode:'nntp',host:'',port:'',name:'',email:'',encoding:'utf-8',headers:500,keep:7500,subscriptions:[]};view='settings';render()}
const catalogs=new Map();
function catalogKey(s){return JSON.stringify(serverEndpoint(s))}
function news(path,params={},server=currentServer()){return nntp(path,{...serverEndpoint(server),...params})}
async function subscribe(){
 captureSettings();const target=settingsDraft;
 try{
  const key=catalogKey(target);let names=target.mode==='nntp'?catalogs.get(key):groups;
  if(!names){toast('正在載入 groups…');const result=await news('groups',{},target);names=result.groups;catalogs.set(key,names)}
  if(view!=='settings'||settingsDraft!==target)return;
  catalog=[...names].sort((a,b)=>a.localeCompare(b));subscriptionSelection=new Set(target.subscriptions);subscriptionQuery='';view='subscriptions';render();
 }catch(e){document.getElementById('form-error').textContent=e.message}
}
function subscriptionRows(){return catalog.filter(g=>g.toLowerCase().includes(subscriptionQuery.toLowerCase())).map(g=>`<div class="group-row">${btn(g,'toggle-sub',`${esc(g)}${subscriptionSelection.has(g)?'<span class="check">✓</span>':''}`,`class="subscription-choice" aria-pressed="${subscriptionSelection.has(g)}" data-group="${esc(g)}"`)}</div>`).join('')||'<p class="empty">No Results</p>'}
function subscriptionScreen(){return nav(btn('取消','cancel-subscriptions'),'',btn('完成','save-subscriptions','完成'))+`<div class="search">${icon('search')}<input id="group-search" type="search" aria-label="搜尋群組" placeholder="搜尋" value="${esc(subscriptionQuery)}"></div><div class="scroll subscription-list">${subscriptionRows()}</div>`}
function wireScreen(){
 if(view==='settings')document.getElementById('server-form').addEventListener('input',()=>{captureSettings();app.querySelector('[data-action="save-server"]').disabled=!settingsValid();document.getElementById('form-error').textContent=settingsIssue()});
 if(view==='subscriptions')document.getElementById('group-search').addEventListener('input',e=>{subscriptionQuery=e.target.value;app.querySelector('.subscription-list').innerHTML=subscriptionRows()});
 document.getElementById('search')?.addEventListener('input',e=>{query=e.target.value;document.getElementById('thread-list').innerHTML=threadRows()});
 if(view==='compose'){
  for(const id of ['subject','body'])document.getElementById(id).addEventListener('input',e=>{state.draft[id]=e.target.value;save();updateSendStatus()});
  for(const photoInput of ['photo-input','camera-input'])document.getElementById(photoInput).addEventListener('change',async e=>{
   if(attachingImages||!state.draft)return;
   const targetDraft=state.draft,valid=[];
   for(const file of e.target.files){
    if(!/^image\/(png|jpeg|webp|gif)$/.test(file.type)){toast('只支援 PNG、JPEG、WebP 或 GIF');continue}
    if(file.size>5*1024*1024){toast('每張相上限 5 MB');continue}
    valid.push(file);
   }
   const batch=selectAttachments(draftImages.length,valid);
   if(batch.rejected)toast(`最多只可以加 3 張相；其餘 ${batch.rejected} 張未加入。`);
   if(!batch.accepted.length)return;
   attachingImages=true;render();
   try{
    for(const file of batch.accepted){
     try{
      const src=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=()=>reject(Error('未能讀取相片，請再選擇。'));r.readAsDataURL(file)});
      if(state.draft!==targetDraft)break;
      if(draftImages.length<MAX_ATTACHMENTS)draftImages.push(src);
     }catch(error){toast(error.message)}
    }
   }finally{attachingImages=false;if(view==='compose')render()}
  });
 }
 // Pointer Events cover touch, pen and desktop drag; wheel covers trackpads.
 bindArticleGestures(document.getElementById('article-scroll'),{
  onSwipe:moveMessage,
  onIntent:()=>{suppressArticleLinkClickUntil=performance.now()+500}
 });
 const scroller=document.getElementById('thread-list');let gesture=null,suppressClickUntil=0,pull=null;
 // Delegate to the list: a swipe beginning on any nested reply belongs to
 // that reply's whole thread. Pointer events also let desktop users drag.
 scroller?.addEventListener('pointerdown',e=>{
  if(!e.isPrimary||e.button!==0){gesture=null;return}
  suppressClickUntil=0;
  const row=e.target.closest('.thread-row[data-thread]');
  gesture=row?{id:row.dataset.thread,x:e.clientX,y:e.clientY,pointerId:e.pointerId}:null;
 });
 scroller?.addEventListener('pointermove',e=>{
  if(!gesture||gesture.pointerId!==e.pointerId)return;
  if(swipeDirection(gesture,{x:e.clientX,y:e.clientY})&&!scroller.hasPointerCapture(e.pointerId))scroller.setPointerCapture(e.pointerId);
 });
 scroller?.addEventListener('pointercancel',()=>{gesture=null});
 scroller?.addEventListener('pointerup',e=>{
  if(!gesture||gesture.pointerId!==e.pointerId)return;
  const start=gesture;gesture=null;
  const end={x:e.clientX,y:e.clientY};
  if(!swipeDirection(start,end))return;
  suppressClickUntil=performance.now()+500;
  const action=threadSwipeAction(start,end,expanded.has(start.id));
  if(action)setThreadExpanded(start.id,action==='expand');
 });
 scroller?.addEventListener('click',e=>{
  if(performance.now()<suppressClickUntil){e.preventDefault();e.stopImmediatePropagation()}
 },true);
 scroller?.addEventListener('touchstart',e=>{pull=scroller.scrollTop===0&&e.touches.length===1?{x:e.changedTouches[0].clientX,y:e.changedTouches[0].clientY}:null},{passive:true});
 scroller?.addEventListener('touchcancel',()=>{pull=null},{passive:true});
 scroller?.addEventListener('touchend',e=>{
  if(pull){const dx=e.changedTouches[0].clientX-pull.x,dy=e.changedTouches[0].clientY-pull.y;if(dy>100&&dy>Math.abs(dx)*1.7)refresh()}
  pull=null;
 },{passive:true});
}
function revealMessage(id){
 const scroll=document.getElementById('thread-list');
 const row=scroll&&[...scroll.querySelectorAll('.thread-row[data-message]')].find(el=>el.dataset.message===id);
 if(!row)return;
 const bounds=scroll.getBoundingClientRect(),rect=row.getBoundingClientRect();
 if(rect.top<bounds.top+8)scroll.scrollTop+=rect.top-bounds.top-8;
 else if(rect.bottom>bounds.bottom-8)scroll.scrollTop+=rect.bottom-bounds.bottom+8;
 listScroll=scroll.scrollTop;
}
function rememberPost(){
 try{sessionStorage.setItem(postContextKey,JSON.stringify({serverId,group,threadId,messageId:selectedMessageId,expanded:[...expanded],latest}))}catch{}
}
function restorePost(){
 try{
  const context=JSON.parse(readMigratedStorage(sessionStorage,postContextKey,legacyPostContextKey));
  const t=state.threads.find(t=>t.id===context?.threadId&&t.server===context.serverId&&t.group===context.group);
  if(!t?.messages.some(m=>m.id===context.messageId))return;
  serverId=context.serverId;group=context.group;threadId=t.id;selectedMessageId=context.messageId;
  expanded=new Set(context.expanded||[]);expanded.add(t.id);latest=!!context.latest;view='list';
 }catch{}
}
function loadStoredState(){
 try{
  const stored=storedData();if(stored===null)return save();
  const fresh=JSON.parse(stored);
  if(fresh?.version!==1||!Array.isArray(fresh.threads)||!Array.isArray(fresh.servers))return false;
  const images=new Map([...state.threads.flatMap(t=>t.messages.filter(m=>m.images?.length).map(m=>[m.id,m.images])),...stagedImages]);
  upgradeHierarchy(fresh);
  restoreAttachmentCache(fresh,images);
  state=fresh;return true;
 }catch{return false}
}
const downloadDialog=document.createElement('dialog');downloadDialog.className='download-dialog';downloadDialog.setAttribute('aria-label','Download Messages');document.body.append(downloadDialog);
function cancelLiveRefresh(){liveRefreshToken++;refreshing=false;if(downloadDialog.open)downloadDialog.close('cancel')}
function positionDownloadDialog(){const phone=app.closest('.phone').getBoundingClientRect();downloadDialog.style.left=`${phone.left+phone.width/2}px`;downloadDialog.style.top=`${phone.top+phone.height/2}px`}
window.addEventListener('resize',()=>{if(downloadDialog.open)positionDownloadDialog()});
function chooseDownload(pending,older=false){
 return new Promise(resolve=>{
  let settled=false;
  const finish=value=>{if(settled)return;settled=true;downloadDialog.close();resolve(value)};
  downloadDialog.innerHTML=`<div class="download-alert"><h3>${esc(group)}</h3><p>There are ${pending.length.toLocaleString()} ${older?'older':'new'} message headers<br>to download:</p><label class="download-quantity">Download <select id="download-count" aria-label="下載數量"><option value="500">500</option><option value="1000">1,000</option><option value="2000">2,000</option><option value="more">More…</option><option value="all">All (${pending.length.toLocaleString()})</option></select></label><input id="download-more" aria-label="更多下載數量" type="number" min="501" step="1" value="1000" hidden><button data-choice="next"></button>${older?'':'<button data-choice="latest"></button>'}<button data-choice="cancel">Cancel</button></div>`;
  const select=downloadDialog.querySelector('select'),custom=downloadDialog.querySelector('input');
  const count=()=>select.value==='all'?'all':select.value==='more'?Number(custom.value):Number(select.value);
  const update=()=>{
   custom.hidden=select.value!=='more';
   const n=count(),valid=n==='all'||Number.isInteger(n)&&n>0&&(select.value!=='more'||n>500);
   for(const b of downloadDialog.querySelectorAll('[data-choice]:not([data-choice="cancel"])')){
    b.disabled=!valid;const label=n==='all'?`all ${pending.length.toLocaleString()}`:Math.min(Number(n)||0,pending.length).toLocaleString();
    b.textContent=older?`Get ${label} older headers`:`Get ${b.dataset.choice==='next'?'next':'newest'} ${label} headers`;
   }
  };
  select.onchange=update;custom.oninput=update;update();
  downloadDialog.onclick=e=>{const choice=e.target.closest('[data-choice]')?.dataset.choice;if(choice==='cancel')finish(null);else if(choice)finish({count:count(),order:older?'latest':choice});else if(e.target===downloadDialog)finish(null)};
  downloadDialog.addEventListener('close',()=>{if(!settled){settled=true;resolve(null)}},{once:true});
  positionDownloadDialog();downloadDialog.showModal();
 });
}
async function refreshLive(older=false){
 if(refreshing)return;
 refreshing=true;const token=++liveRefreshToken,sid=serverId,g=group,server=structuredClone(currentServer()),initialView=view;
 const previous=state.threads.filter(t=>t.server===sid&&t.group===g).flatMap(t=>t.messages);
 const known=previous.map(m=>m.number).filter(Number.isSafeInteger),before=new Set(previous.map(m=>m.id));
 const messageId=view==='article'?currentThread()?.messages[messageIndex]?.id:null;
 const scroll=document.getElementById('thread-list')?.scrollTop??listScroll;
 const articleScroll=document.getElementById('article-scroll')?.scrollTop||0;
 const cursorKey=JSON.stringify([sid,g]),cursor=state.downloadCursors?.[cursorKey]||0;
 const active=()=>token===liveRefreshToken&&serverId===sid&&group===g&&view===initialView;
 app.querySelector('[data-action="refresh"]')?.classList.add('loading');
 try{
  const inventory=await news('numbers',{group:g},server);if(!active())return;
  const plan=downloadInventory(inventory.numbers,known,cursor,older);
  if(!plan.pending.length){toast(older?'No More Older Messages':`No New Messages${plan.olderCount?` · ${plan.olderCount} 篇舊文可用 Get Older Messages 載入`:''}`);return}
  let choice={count:Math.min(Number(server.headers)||500,500),order:older?'latest':'next'};
  if(plan.pending.length>500)choice=await chooseDownload(plan.pending,older);
  if(!choice||!active())return;
  const selected=chooseNumbers(plan.pending,choice.count,choice.order);let received=0,added=0;
  for(const batch of batches(selected)){
   const result=await headersBatch(server,g,batch);if(!active())return;
   const threads=mergeHeaders(state.threads,result.messages,sid,g);
   const high=result.messages.reduce((max,m)=>Math.max(max,m.number),plan.highWater);
   const cursors={...state.downloadCursors,[cursorKey]:Math.max(cursor,high)};
   if(!save({...state,threads,downloadCursors:cursors}))throw Error('本機儲存空間不足，已保留之前成功下載嘅批次。');
   state.threads=threads;state.downloadCursors=cursors;
   received+=batch.length;added+=result.messages.filter(m=>!before.has(m.id)).length;
   toast(`Downloading ${received.toLocaleString()} / ${selected.length.toLocaleString()}…`);
  }
  if(!active())return;
  if(messageId){const t=state.threads.find(t=>t.server===sid&&t.group===g&&t.messages.some(m=>m.id===messageId));if(t){threadId=t.id;messageIndex=t.messages.findIndex(m=>m.id===messageId)}}
  const visible=list();
  readingThreadIds=view==='article'?[...new Set([...readingThreadIds,threadId,...visible.map(t=>t.id)])].filter(id=>state.threads.some(t=>t.id===id)):visible.map(t=>t.id);readingRoute=readingSequence(readingThreads());
  listScroll=scroll;render();if(view==='article')document.getElementById('article-scroll').scrollTop=articleScroll;
  toast(`${added.toLocaleString()} ${older?'Older':'New'} Messages · Live · server 共 ${inventory.count.toLocaleString()} 篇`);
 }catch(e){if(active()){render();toast(`下載未完成：${e.message}`)}}
 finally{if(token===liveRefreshToken){refreshing=false;const b=app.querySelector('[data-action="refresh"]');b?.classList.remove('loading');if(b)b.disabled=false}}
}
async function refresh(){
 if(currentServer()?.mode==='nntp'){await refreshLive();return}
 if(refreshing)return;
 refreshing=true;const refreshView=view;
 const listElement=document.getElementById('thread-list');if(listElement)listScroll=listElement.scrollTop;
 const articlePosition=document.getElementById('article-scroll')?.scrollTop||0;
 const oldMessageId=view==='article'?currentThread()?.messages[messageIndex]?.id:null;
 const before=new Set(state.threads.flatMap(t=>t.server===serverId&&t.group===group?t.messages.map(m=>m.id):[]));
 app.querySelector('[data-action="refresh"]')?.classList.add('loading');
 await new Promise(requestAnimationFrame);
 // The prototype repository is localStorage, not a simulated network delay.
 if(view!==refreshView){refreshing=false;const b=app.querySelector('[data-action="refresh"]');b?.classList.remove('loading');if(b)b.disabled=false;return}
 const loaded=loadStoredState();refreshing=false;
 if(!loaded){const b=app.querySelector('[data-action="refresh"]');b?.classList.remove('loading');if(b)b.disabled=false;toast('未能讀取本機資料；保留目前畫面。');return}
 if(view==='article'){
  const index=currentThread()?.messages.findIndex(m=>m.id===oldMessageId)??-1;
  if(index<0)view='list';else messageIndex=index;
 }
 const added=state.threads.filter(t=>t.server===serverId&&t.group===group).flatMap(t=>t.messages.filter(m=>!before.has(m.id)));
 render();app.querySelector('.screen').style.animation='none';
 if(view==='list'&&selectedMessageId)revealMessage(selectedMessageId);
 if(view==='article')document.getElementById('article-scroll').scrollTop=articlePosition;
 toast(added.length?`${added.length} New Message${added.length===1?'':'s'} · 本機資料已更新`:'已重新載入本機文章 · 回覆已保留');
}

async function handle(action,b){
 const tid=b?.dataset.thread,index=Number(b?.dataset.index||0);
 switch(action){
 case 'connect-nntp':{
  let server=state.servers.find(s=>s.mode==='nntp');
  if(!server){server={...state.servers[0],id:'live-twonil',host:'news.twonil.hk',port:119,mode:'nntp',headers:500,subscriptions:['general.chat','general.soccer_n_chat'],name:'',email:''};state.servers.push(server);save()}
  serverId=server.id;showGroups();toast('Live server 已加入，揀群組開始讀取。');break;
 }
 case 'groups':articleRequest++;showGroups();break;
 case 'edit':editing=!editing;render();break;
 case 'group':openGroup(b.dataset.group,b.dataset.server);break;
 case 'settings':settings(b.dataset.server);break;
 case 'add-server':settings(null);break;
 case 'about':toast('yrNewsEx · Demo 本機示例／Live 真實 NNTP');break;
 case 'unsubscribe':{const s=state.servers.find(s=>s.id===b.dataset.server);s.subscriptions=s.subscriptions.filter(g=>g!==b.dataset.group);save();render();break}
 case 'expand':setThreadExpanded(tid,!expanded.has(tid));break;
 case 'article':openArticle(tid,index);break;
 case 'back-list':articleRequest++;view='list';render();break;
 case 'prev-message':case 'next-message':moveMessage(action==='next-message'?1:-1);break;
 case 'prev-thread':case 'next-thread':{const ts=readingThreads(),i=ts.findIndex(t=>t.id===threadId)+(action==='next-thread'?1:-1);if(ts[i])openArticle(ts[i].id);break}
 case 'refresh':refresh();break;
 case 'group-actions':actions([['Mark All Read','mark-all'],[unreadOnly?'Show All Messages':'Show Unread Only','filter-unread'],[favouritesOnly?'Show All Favourites & Others':'Show Favourites Only','filter-star'],['Get Older Messages','older'],[latest?'Sort Threads by Original Post':'Sort Threads by Latest Reply','sort']]);break;
 case 'article-actions':actions([['Mark Thread Read','mark-thread'],[currentThread().star?'Remove Favourite':'Add Favourite','star'],['Mark Message Unread','mark-message-unread']]);break;
 case 'mark-all':state.threads.filter(t=>t.server===serverId&&t.group===group).forEach(markThreadRead);closeSheet();save();render();break;
 case 'mark-thread':markThreadRead(currentThread());closeSheet();save();render();break;
 case 'mark-message-unread':currentThread().messages[messageIndex].read=false;closeSheet();save();view='list';render();break;
 case 'star':currentThread().star=!currentThread().star;closeSheet();save();toast(currentThread().star?'Added to Favourites':'Removed from Favourites');break;
 case 'filter-unread':unreadOnly=!unreadOnly;closeSheet();render();break;
 case 'filter-star':favouritesOnly=!favouritesOnly;closeSheet();render();break;
 case 'sort':latest=!latest;closeSheet();render();break;
 case 'older':{closeSheet();if(currentServer()?.mode==='nntp'){refreshLive(true);break}const id=serverId+group;if(oldPages.has(id)){toast('No More Messages · 示例舊文已載入');break}oldPages.add(id);state.threads.push({id:crypto.randomUUID(),server:serverId,group,subject:'上星期嘅話題（較舊示例）',stamp:0,star:false,messages:[{id:crypto.randomUUID(),author:'舊朋友',email:'reader@example.invalid',time:'10:00',body:'呢篇係模擬載入嘅較舊文章。',images:[],read:false}]});save();render();toast('1 Older Message · 已加入清單底部');break}
 case 'compose':startCompose();break;
 case 'reply':startCompose(true);break;
 case 'replace-draft':case 'replace-reply':closeSheet();createDraft(action==='replace-reply');break;
 case 'resume-draft':closeSheet();composeReturn='list';serverId=state.draft.server;group=state.draft.group;if(currentServer()?.mode==='nntp'&&(!currentServer().name?.trim()||!validEmail(currentServer().email||''))){settings(serverId);toast('請先設定呢個 server 嘅 Name 同 Email。');break}view='compose';render();break;
 case 'cancel-compose':actions([['Save Draft','save-draft'],['Discard Draft','discard-draft']],'取消撰寫');break;
 case 'save-draft':save();closeSheet();view=composeReturn==='article'&&currentThread()?'article':'list';render();toast('Draft Saved · 相片只保留喺本次頁面');break;
 case 'discard-draft':state.draft=null;draftImages=[];save();closeSheet();view=composeReturn==='article'&&currentThread()?'article':'list';render();break;
 case 'photo':if(attachingImages||draftImages.length>=MAX_ATTACHMENTS){toast('最多只可以加 3 張相');break}actions([['Take a New Photo','take-photo'],['Choose Existing','choose-photo'],...(!liveDraft()?[['加入示範圖片','demo-photo']]:[])],'Attach Photo');break;
 case 'take-photo':closeSheet();document.getElementById('camera-input').click();break;
 case 'renew-post-id':if(!sending&&state.draft?.duplicatePost){renewPostId(state.draft);save();render();toast('新識別碼已準備好；按 Send 先會重新發送。')}break;
 case 'choose-photo':closeSheet();document.getElementById('photo-input').click();break;
 case 'demo-photo':closeSheet();if(attachingImages)break;{const batch=selectAttachments(draftImages.length,[sampleImage]);draftImages.push(...batch.accepted);if(batch.rejected)toast('最多只可以加 3 張相');render()}break;
 case 'remove-image':if(attachingImages)break;draftImages.splice(index,1);render();break;
 case 'send':{
  if(sending||attachingImages||!state.draft)break;
  sending=true;b.disabled=true;
  try{
   const d=state.draft;
   if(liveDraft()){
    if(!d.postId)d.postId=crypto.randomUUID();
    const payload=await prepareLivePayload(d,draftImages);delete d.deliveryError;delete d.duplicatePost;save();
    app.querySelectorAll('input,textarea,button').forEach(el=>el.disabled=true);
    toast('正在發送到 NNTP server…');
    const result=await postLive(payload);
    const server=state.servers.find(s=>s.id===d.server);
    state.draft=null;draftImages=[];serverId=d.server;group=d.group;threadId=d.parent;
    selectedMessageId=result.id;view='list';save();rememberPost();render();
    toast(`${d.parent?'Reply':'Message'} Sent · 按 Refresh 載入 · ${result.encoding.toUpperCase()}`);
    break;
   }
   const result=commitDraft(state,d,draftImages,save);
   // POST commits to the repository only. Keep the pre-refresh cache,
   // expanded rows, filters, counts and scroll position exactly as they were.
   state.draft=null;serverId=d.server;group=d.group;threadId=result.thread.id;
   selectedMessageId=result.message.id;
   if(draftImages.length)stagedImages.set(result.message.id,draftImages);
   draftImages=[];view='list';
   rememberPost();render();
   toast(`${d.parent?'Reply':'Message'} Sent · 按 Refresh 載入（本機示例）`);
  }catch(e){if(state.draft){state.draft.deliveryError=e.message;state.draft.duplicatePost=!!e.duplicate;save()}toast(e.message)}finally{sending=false;if(view==='compose')render()}
  break;
 }
 case 'close-sheet':closeSheet();break;
 case 'cancel-settings':view=settingsReturn;render();break;
 case 'save-server':{
  captureSettings();if(!settingsValid()){document.getElementById('form-error').textContent='請填寫 Server、Name 同有效 Email。';break}
  b.disabled=true;
  try{
   if(!settingsDraft.id){const result=await news('groups',{},settingsDraft);catalogs.set(catalogKey(settingsDraft),result.groups)}
   const saved={...structuredClone(settingsDraft),id:settingsDraft.id||crypto.randomUUID()};
   const servers=settingsDraft.id?state.servers.map(s=>s.id===saved.id?saved:s):[...state.servers,saved];
   if(!save({...state,servers}))throw Error('未能儲存 server 設定，請再試。');
   state.servers=servers;serverId=saved.id;showGroups();
  }catch(e){document.getElementById('form-error').textContent=e.message;b.disabled=false}
  break;
 }
 case 'subscribe':subscribe();break;
 case 'toggle-sub':{const g=b.dataset.group;subscriptionSelection.has(g)?subscriptionSelection.delete(g):subscriptionSelection.add(g);b.setAttribute('aria-pressed',String(subscriptionSelection.has(g)));b.innerHTML=esc(g)+(subscriptionSelection.has(g)?'<span class="check">✓</span>':'');break}
 case 'cancel-subscriptions':view='settings';render();break;
 case 'save-subscriptions':settingsDraft.subscriptions=[...subscriptionSelection].sort((a,b)=>a.localeCompare(b));view='settings';render();break;
 case 'delete-server':actions([['Delete Server（移除本機資料）','confirm-delete','class="danger"']],'移除本機 server、訂閱及已下載文章？');break;
 case 'confirm-delete':{const id=settingsDraft.id;state.servers=state.servers.filter(s=>s.id!==id);state.downloadCursors=Object.fromEntries(Object.entries(state.downloadCursors||{}).filter(([key])=>JSON.parse(key)[0]!==id));state.threads=state.threads.filter(t=>t.server!==id);if(state.draft?.server===id){state.draft=null;draftImages=[]}serverId=state.servers[0]?.id;closeSheet();save();showGroups();break}
 }
}
app.addEventListener('click',e=>{
 const link=e.target.closest('a[href]');if(!link)return;
 if(performance.now()<suppressArticleLinkClickUntil){e.preventDefault();e.stopImmediatePropagation();return}
 if(e.defaultPrevented||e.button!==0||e.metaKey||e.ctrlKey||e.shiftKey||e.altKey)return;
 e.preventDefault();
 openExternalLink(link.href);
},true);
for(const root of [app,sheet])root.addEventListener('click',e=>{const b=e.target.closest('button[data-action]');if(b&&!b.disabled)handle(b.dataset.action,b)});
sheet.addEventListener('click',e=>{if(e.target===sheet)closeSheet()});
document.addEventListener('keydown',e=>{if(view!=='article'||sheet.open||e.target.matches('input,textarea,select'))return;if(e.key==='ArrowRight'){e.preventDefault();moveMessage(1)}if(e.key==='ArrowLeft'){e.preventDefault();moveMessage(-1)}});
restorePost();
render();
if(view==='list'&&selectedMessageId)revealMessage(selectedMessageId);
