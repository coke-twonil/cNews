// Thread only by Message-ID / References. Never group unrelated matching subjects.
export function mergeHeaders(existing, rows, server, group){
 const old=existing.filter(t=>t.server===server&&t.group===group);
 const previous=new Map(old.flatMap(t=>t.messages.map(m=>[m.id,m])));
 const messages=new Map(previous);
 for(const row of rows){
  const saved=previous.get(row.id),date=new Date(row.createdAt);
  messages.set(row.id,{...row,parentId:row.references.at(-1)||null,time:Number.isNaN(+date)?'':date.toLocaleTimeString('zh-HK',{hour:'2-digit',minute:'2-digit',hour12:false}),body:'',images:[],read:false,...saved,...row});
 }
 // References include missing ancestors: those still connect separate branches.
 const parent=new Map();
 const find=id=>{let path=[],at=id;while(parent.has(at)&&parent.get(at)!==at){path.push(at);at=parent.get(at)}for(const x of path)parent.set(x,at);return at};
 const join=(a,b)=>{const x=find(a),y=find(b);if(x!==y)parent.set(x,y)};
 for(const m of messages.values())for(const ref of m.references||[])join(m.id,ref);
 const buckets=new Map();
 for(const m of messages.values()){const root=find(m.id);if(!buckets.has(root))buckets.set(root,[]);buckets.get(root).push(m)}
 const threads=[...buckets].map(([root,msgs])=>{
  msgs.sort((a,b)=>a.number-b.number);
  const head=msgs.find(m=>!msgs.some(p=>p.id===m.parentId))||msgs[0];
  const prior=old.find(t=>t.messages.some(m=>msgs.some(n=>n.id===m.id)));
  return {id:prior?.id||`${server}:${group}:${root}`,server,group,subject:head.subject.replace(/^(Re:\s*)+/i,''),stamp:Math.min(...msgs.map(m=>m.number)),latest:Math.max(...msgs.map(m=>m.number)),star:prior?.star||false,messages:msgs};
 });
 return [...existing.filter(t=>t.server!==server||t.group!==group),...threads];
}
export async function nntp(path,params={}){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),25000);
 try{
  const response=await fetch(`http://127.0.0.1:8767/${path}?${new URLSearchParams(params)}`,{headers:{'X-cNews':'reader'},signal:controller.signal});
  const result=await response.json();if(!response.ok)throw new Error(result.error||'NNTP 連線失敗');return result;
 }catch(e){throw new Error(e.name==='AbortError'?'NNTP 連線逾時':e.message==='Failed to fetch'?'未能連接 NNTP helper，請啟動 scripts/serve.py':e.message)}finally{clearTimeout(timer)}
}

// Older headers may join two formerly separate cached branches. Do not restore
// the obsolete thread from localStorage when saving the regrouped result.
export function withoutSupersededThreads(snapshot,stored){
 if(!stored)return stored;
 const live=new Set(snapshot.servers.filter(s=>s.mode==='nntp').map(s=>s.id));
 const known=new Set(snapshot.threads.map(t=>t.id));
 const messages=new Set(snapshot.threads.filter(t=>live.has(t.server)).flatMap(t=>t.messages.map(m=>JSON.stringify([t.server,t.group,m.id]))));
 return {...stored,threads:stored.threads.filter(t=>known.has(t.id)||!live.has(t.server)||!t.messages.some(m=>messages.has(JSON.stringify([t.server,t.group,m.id]))))};
}

// Saved image bytes are deliberately kept out of localStorage. Re-fetch a
// previously read article if its images are missing or its decoder predates MIME.
export function needsArticleContent(message){
 return !message.bodyLoaded||message.contentVersion!==3||message.imageCount!==(message.images?.length||0);
}
export function applyArticleContent(message,result){
 Object.assign(message,{body:result.body,contentParts:result.contentParts,images:result.images||[],imageWarnings:result.imageWarnings||[],bodyLoaded:true,contentVersion:result.contentVersion,imageCount:(result.images||[]).length});
}

export function serverEndpoint(server){return {host:server.host,port:server.port||119,tls:!!server.tls||Number(server.port)===563}}
export async function headersBatch(server,group,numbers){
 const response=await fetch('http://127.0.0.1:8767/headers',{method:'POST',headers:{'X-cNews':'reader','Content-Type':'application/json'},body:JSON.stringify({...serverEndpoint(server),group,numbers})});
 const result=await response.json();if(!response.ok)throw Error(result.error||'未能下載文章');return result;
}
