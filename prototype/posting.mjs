import {replyDraft} from './model.mjs';

export function validEmail(value){return /^[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+$/.test((value||'').trim())}
export function validSender(d){return Boolean(d.senderName?.trim()&&validEmail(d.senderEmail)&&!/[\r\n]/.test(d.senderName))}
export function sendBlockReason(d,{live=false,attachingImages=false,sending=false}={}){
 if(sending)return '正在發送，請稍候。';
 if(attachingImages)return '圖片仍然載入緊，完成後先可以 Send。';
 if(!d)return '未有草稿。';
 if(live){
  if(!d.senderName?.trim())return '請填寫公開顯示嘅 Name，先可以 Send。';
  if(/[\r\n]/.test(d.senderName))return 'Name 唔可以包含換行。';
  if(!d.senderEmail?.trim())return '請填寫 Email，格式例如 nickname@example.invalid。';
  if(!validEmail(d.senderEmail))return 'Email 格式唔正確，要用「名稱@網域」，例如 nickname@example.invalid。';
 }
 if(!d.subject?.trim())return '請填寫 Subject，先可以 Send。';
 if(!d.body?.trim())return '請填寫正文，先可以 Send。';
 return '';
}
export function livePayload(d,images){
 if(!validSender(d))throw Error('請填寫公開顯示嘅 Name 同有效 Email');
 if(!d.subject.trim()||!d.body.trim())throw Error('請填寫主題同正文');
 if(images.length>3)throw Error('最多只可以加 3 張相');
 return {host:d.host||'news.twonil.hk',port:d.port||119,tls:!!d.tls,layoutVersion:1,group:d.group,subject:d.subject,body:d.body,name:d.senderName.trim(),email:d.senderEmail.trim(),postId:d.postId,replyTo:d.replyTo||null,references:d.references||[],encoding:d.encoding||'utf-8',images};
}
export async function prepareLiveReply(thread,message,fetchMessage){
 const history=[],seen=new Set();let cursor=message;
 while(cursor&&history.length<4&&!seen.has(cursor.id)){
  seen.add(cursor.id);
  if(!cursor.bodyLoaded){
   const result=await fetchMessage(cursor.id);
   if(result.id!==cursor.id)throw Error('引用文章身份不符，請 Refresh');
   const date=new Date(result.meta.createdAt);
   cursor={...result.meta,body:result.body,bodyLoaded:true,parentId:result.meta.references.at(-1)||null,time:date.toLocaleTimeString('zh-HK',{hour:'2-digit',minute:'2-digit',hour12:false}),date:date.toLocaleDateString('en-GB',{day:'2-digit',month:'2-digit'})};
  }else if(cursor.createdAt){
   cursor={...cursor,date:new Date(cursor.createdAt).toLocaleDateString('en-GB',{day:'2-digit',month:'2-digit'})};
  }
  history.push(cursor);
  const parent=cursor.parentId||cursor.references?.at(-1);
  cursor=parent?(thread.messages.find(m=>m.id===parent)||{id:parent}):null;
 }
 const draft=replyDraft({...thread,messages:history},history[0]);
 draft.references=[...new Set([...(history[0].references||[]),message.id])].slice(-100);
 return draft;
}
export async function postLive(payload){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),60000);
 try{
  const response=await fetch('http://127.0.0.1:8767/post',{method:'POST',headers:{'X-cNews':'reader','Content-Type':'application/json'},body:JSON.stringify(payload),signal:controller.signal});
  const result=await response.json();
  if(!response.ok){const error=new Error(result.error||'Server 拒絕發文');error.uncertain=result.uncertain;error.duplicate=result.duplicate;throw error}
  if(!result.accepted)throw Error('未收到 server 接受發文嘅回覆');
  return result;
 }catch(e){if(e.name==='AbortError'||e.message==='Failed to fetch'){const error=new Error('連線中斷或逾時，發送結果未確認；請先 Refresh 檢查，草稿已保留。');error.uncertain=true;throw error}throw e}finally{clearTimeout(timer)}
}

// A retry of identical content keeps its ID; edited text/identity/images gets a
// fresh ID. This also covers adding a photo to a previously attempted draft.
export async function prepareLivePayload(d,images,{uuid=()=>crypto.randomUUID(),hash=async text=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text))),b=>b.toString(16).padStart(2,'0')).join('')}={}){
 const payload=livePayload(d,images),{postId,...content}=payload;
 const fingerprint=await hash(JSON.stringify(content));
 if(!d.postId||(d.postFingerprint&&d.postFingerprint!==fingerprint)){d.postId=uuid();d.postBrand='cnews'}
 d.postFingerprint=fingerprint;
 return {...payload,postId:d.postId,postBrand:d.postBrand||'cnews'};
}
export function renewPostId(d,uuid=()=>crypto.randomUUID()){
 d.postBrand='cnews';d.postId=uuid();delete d.postFingerprint;delete d.duplicatePost;delete d.deliveryError;
}
