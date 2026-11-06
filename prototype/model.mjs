export const groups = ['club.arsenal','club.liverpool','club.manutd','club.spurs','game.ps4','general.chat','general.soccer_n_chat','talk.JapanTV','talk.MilkJapan','talk.ele_device'];
export const MAX_ATTACHMENTS=3;
export function selectAttachments(currentCount,candidates){
 const slots=Math.max(0,MAX_ATTACHMENTS-currentCount);
 return {accepted:candidates.slice(0,slots),rejected:Math.max(0,candidates.length-slots)};
}
export function restoreAttachmentCache(state,cache){
 for(const thread of state.threads)for(const message of thread.messages){
  if(cache.has(message.id))message.images=[...cache.get(message.id)];
 }
 return state;
}
export const sampleImage = 'data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="420" viewBox="0 0 640 420"><rect width="640" height="420" fill="#243c42"/><circle cx="320" cy="220" r="145" fill="#eee3c8"/><circle cx="320" cy="220" r="120" fill="#b96531"/><path d="M230 180 Q320 100 405 220 Q320 320 230 250Z" fill="#efbe64"/><path d="M235 240L400 180M240 190L390 255" stroke="#67936d" stroke-width="14"/><text x="30" y="40" fill="#fff" font-size="20" font-family="sans-serif">DEMO PHOTO · 示範圖片</text></svg>');
const subjects = ['今晚食乜好？','有冇人用緊新 reader？','APM 間咖啡店仲有冇開？','週末去邊度行下','想搵一部細啲嘅手機','講下最近睇緊嘅戲','今日個天好舒服','分享一張晚餐相'];
const authors = ['阿明','路人甲','Coffee lover','散步的人','小文','Film fan','阿晴','食家'];
// Siblings and nested branches, rather than nine replies to the root.
const sampleParents = [null,0,1,2,1,0,5,6,5];
export function seed(){
 const threads = groups.flatMap((group,g) => (group==='general.chat'?subjects:group==='general.soccer_n_chat'?['今場個陣點睇？','Hand ball','週末一齊睇波']:['開個新話題','最近有咩好介紹？']).map((subject,i)=>{
  const count = group==='general.chat'?[1,2,9,4,2,3,8,9][i]:i+1;
  return {id:`t-${g}-${i}`,server:'s1',group,subject,stamp:100-i,star:i===2,messages:Array.from({length:count},(_,n)=>({id:`m-${g}-${i}-${n}`,author:authors[(i+n)%authors.length],email:'reader@example.invalid',time:`${19-Math.floor(i/2)}:${String(2+n*4).padStart(2,'0')}`,body:n===0?(i===2?'以前成日去坐下，最近經過見到好似冇開。\n有冇人知搬咗去邊？':i===7?'今晚簡單食，分享張相先。':'今日想同大家傾下。\n\n你哋覺得點？'):['下次要試下。\n我上次去都幾靜，可以慢慢坐。','我都想知，有消息再講。','多謝分享！'][n%3],quote:n>0?'以前成日去坐下，最近經過見到好似冇開。\n有冇人知搬咗去邊？':'',images:i===7&&n===0?[sampleImage]:[],read:n>0&&n<3}))};
 }));
 return upgradeHierarchy({version:1,servers:[{id:'s1',host:'news.twonil.hk',port:119,name:'示例讀者',email:'reader@example.invalid',encoding:'big5',headers:2000,keep:7500,subscriptions:[...groups]}],threads,draft:null});
}
export function upgradeHierarchy(state){
 for(const thread of state.threads){
  for(const [index,message] of thread.messages.entries()){
   if(Object.hasOwn(message,'parentId'))continue;
   // Only the bundled fixtures have known reply relationships. Legacy user
   // replies have no recoverable parent, so attach them to their thread root.
   const fixtureIndex=/^m-\d+-\d+-(\d+)$/.exec(message.id);
   const parentIndex=fixtureIndex?sampleParents[Number(fixtureIndex[1])]:0;
   message.parentId=index===0?null:thread.messages[parentIndex??0]?.id??null;
  }
 }
 state.hierarchyVersion=1;
 return state;
}
// Iterative depth-first traversal keeps child replies next to their parent.
// Missing parents and cycles are shown once, rather than hidden or looping.
export function messageTree(thread){
 const ids=new Set(thread.messages.map(m=>m.id)),children=new Map(),roots=[];
 thread.messages.forEach((message,index)=>{
  const entry={message,index};
  if(message.parentId&&message.parentId!==message.id&&ids.has(message.parentId)){
   if(!children.has(message.parentId))children.set(message.parentId,[]);
   children.get(message.parentId).push(entry);
  }else roots.push(entry);
 });
 const result=[],visited=new Set();
 function walk(root){
  const stack=[{...root,depth:0}];
  while(stack.length){
   const entry=stack.pop();
   if(visited.has(entry.message.id))continue;
   visited.add(entry.message.id);result.push(entry);
   const replies=children.get(entry.message.id)||[];
   for(let i=replies.length-1;i>=0;i--)stack.push({...replies[i],depth:entry.depth+1});
  }
 }
 roots.forEach(walk);
 thread.messages.forEach((message,index)=>{if(!visited.has(message.id))walk({message,index})});
 return result;
}
export function readingSequence(threads){
 return threads.flatMap(thread=>messageTree(thread).map(({message,index,depth})=>({threadId:thread.id,messageId:message.id,index,depth})));
}
export function adjacentMessage(sequence,threadId,messageId,direction){
 const position=sequence.findIndex(m=>m.threadId===threadId&&m.messageId===messageId);
 if(position<0||![-1,1].includes(direction))return null;
 return sequence[position+direction]??null;
}
export function swipeDirection(start,end){
 const dx=end.x-start.x,dy=end.y-start.y;
 return Math.abs(dx)>80&&Math.abs(dx)>Math.abs(dy)*1.7?(dx<0?1:-1):0;
}
export function threadSwipeAction(start,end,isExpanded){
 const direction=swipeDirection(start,end);
 if(direction===-1)return isExpanded?null:'expand';
 if(direction===1&&isExpanded)return 'collapse';
 return null;
}
export const unread = t => t.messages.filter(m=>!m.read).length;
export function markThreadRead(thread){thread.messages.forEach(m=>m.read=true)}
export function filteredThreads(state,server,group,{query='',unreadOnly=false,favouritesOnly=false,latest=false}={}){
 const q=query.trim().toLocaleLowerCase();
 return state.threads.filter(t=>t.server===server&&t.group===group&&(!unreadOnly||unread(t)>0)&&(!favouritesOnly||t.star)&&(!q||[t.subject,...t.messages.flatMap(m=>[m.author,m.body])].some(s=>s.toLocaleLowerCase().includes(q)))).sort((a,b)=>latest?(b.latest??b.stamp)-(a.latest??a.stamp):b.stamp-a.stamp);
}
export function replyHistory(thread,messageId){
 const byId=new Map(thread.messages.map(m=>[m.id,m])),history=[],visited=new Set();
 let message=byId.get(messageId);
 while(message&&history.length<4&&!visited.has(message.id)){
  history.push(message);visited.add(message.id);message=byId.get(message.parentId);
 }
 return history;
}
// Rebuild history from the parent chain. Reusing a message's existing quoted
// body would duplicate ancestors and could smuggle a fifth generation in.
export function ownMessageText(message){
 const lines=String(message.ownBody??message.body??'').split('\n');
 return lines.filter((line,index)=>{
  if(/^\s*>/.test(line))return false;
  if(/^On .+ wrote:\s*$/.test(line.trim())){
   const following=lines.slice(index+1).find(l=>l.trim());
   if(following&&/^\s*>/.test(following))return false;
  }
  return true;
 }).join('\n').trim();
}
export function quotedHistory(history){
 let text='';
 for(const message of [...history].reverse()){
  const content=[ownMessageText(message),text].filter(Boolean).join('\n\n');
  text=`On ${message.time} ${message.date??'04/11'}, ${message.author} wrote:\n${content.split('\n').map(line=>'> '+line).join('\n')}`;
 }
 return text;
}
export function quotedLines(text){
 return String(text).split('\n').map(line=>{
  let depth=0;
  while(/^\s*>/.test(line)){line=line.replace(/^\s*> ?/,'');depth++}
  return {depth,text:line};
 });
}
export function replyDraft(thread,message){
 const history=replyHistory(thread,message.id);
 return {server:thread.server,group:thread.group,parent:thread.id,replyTo:message.id,quoteMessageIds:history.map(m=>m.id),subject:`Re: ${thread.subject.replace(/^Re:\s*/i,'')}`,body:`\n\n${quotedHistory(history)}`,images:[]};
}
export function validateServer(server){if(!server.host.trim()||/\s/.test(server.host))return '請輸入有效嘅 Server 地址';if(!Number.isInteger(Number(server.port))||server.port<1||server.port>65535)return 'Port 必須介乎 1 至 65535';if(!Number.isInteger(Number(server.headers))||server.headers<1||!Number.isInteger(Number(server.keep))||server.keep<server.headers)return '文章保留數量必須大於或等於每次下載數量';return ''}
export function postDraft(state,draft,images=[]){
 if(images.length>MAX_ATTACHMENTS)throw Error('最多只可以加 3 張相');
 const s=state.servers.find(s=>s.id===draft.server);if(!s)throw Error('Server 不存在');
 if(!draft.subject.trim()||!draft.body.trim())throw Error('請填寫主題同正文');
 const now=new Date();
 const msg={id:crypto.randomUUID(),author:s.name||'示例讀者',email:s.email||'reader@example.invalid',time:new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Hong_Kong',hour:'2-digit',minute:'2-digit'}).format(now),date:new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Hong_Kong',day:'2-digit',month:'2-digit'}).format(now),createdAt:now.toISOString(),body:draft.body.trim(),ownBody:ownMessageText({body:draft.body}),quote:'',images,read:false};
 let thread=state.threads.find(t=>t.id===draft.parent&&t.server===s.id&&t.group===draft.group);
 if(draft.parent&&!thread)throw Error('原本嘅討論串已不存在；草稿仍然保留。');
 if(thread){msg.parentId=thread.messages.find(m=>m.id===draft.replyTo)?.id??thread.messages[0].id;thread.messages.push(msg);thread.latest=Date.now()}else{msg.parentId=null;thread={id:crypto.randomUUID(),server:s.id,group:draft.group,subject:draft.subject.trim(),stamp:Date.now(),star:false,messages:[msg]};state.threads.unshift(thread)}
 state.draft=null;return thread;
}
export function commitDraft(state,draft,images,persist){
 // Persist a candidate first, so failed storage cannot clear the live draft
 // or append a duplicate reply when the user retries Send.
 const candidate={...state,threads:state.threads.map(t=>({...t,messages:[...t.messages]}))};
 const thread=postDraft(candidate,draft,images);
 if(!persist(candidate))throw Error('未能儲存回覆，草稿已保留，請再試。');
 return {state:candidate,thread,message:thread.messages.at(-1)};
}
// The visible cache stays unchanged after POST. Subsequent read/draft saves
// must preserve server-side messages which have not been refreshed into it.
export function mergeRepository(visible,repository){
 if(!repository)return visible;
 const remote=new Map(repository.threads.map(t=>[t.id,t]));
 const known=new Set(visible.threads.map(t=>t.id)),servers=new Set(visible.servers.map(s=>s.id));
 const threads=visible.threads.map(thread=>{
  const stored=remote.get(thread.id);if(!stored)return thread;
  const localMessages=new Map(thread.messages.map(m=>[m.id,m]));
  const storedIds=new Set(stored.messages.map(m=>m.id));
  const messages=[...stored.messages.map(m=>localMessages.get(m.id)??m),...thread.messages.filter(m=>!storedIds.has(m.id))];
  return {...thread,messages,latest:Math.max(thread.latest??thread.stamp,stored.latest??stored.stamp)};
 });
 threads.push(...repository.threads.filter(t=>!known.has(t.id)&&servers.has(t.server)));
 return {...visible,threads};
}
