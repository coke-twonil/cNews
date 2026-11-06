const escapeHtml=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

function trimUrl(raw){
 let url=raw;
 while(url){
  if(/[.,!?;:]$/.test(url)){url=url.slice(0,-1);continue}
  const end=url.at(-1),pairs={')':'(',']':'[','}':'{'};
  if(pairs[end]&&url.split(end).length>url.split(pairs[end]).length){url=url.slice(0,-1);continue}
  break;
 }
 return url;
}

export function linkParts(text){
 const source=String(text),parts=[];
 const pattern=/\b(?:https?:\/\/|www\.)[^\s<>"'，。！？；：、（）【】《》「」『』]+/giu;
 let cursor=0;
 for(const match of source.matchAll(pattern)){
  const label=trimUrl(match[0]);let url;
  try{url=new URL(/^www\./i.test(label)?'https://'+label:label)}catch{continue}
  if(!['https:','http:'].includes(url.protocol)||!url.hostname||url.username||url.password)continue;
  if(match.index>cursor)parts.push({text:source.slice(cursor,match.index)});
  parts.push({text:label,href:url.href});cursor=match.index+label.length;
 }
 if(cursor<source.length)parts.push({text:source.slice(cursor)});
 return parts;
}

export function renderLinks(text){
 return linkParts(text).map(part=>part.href
  ?`<a href="${escapeHtml(part.href)}" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer">${escapeHtml(part.text)}</a>`
  :escapeHtml(part.text)).join('');
}

// Some embedded browsers ignore target=_blank. Keep a same-tab fallback when
// creating a window is refused; no third-party page receives our window.opener.
export function openExternalLink(href,{openWindow=()=>window.open('about:blank','_blank'),navigate=url=>window.location.assign(url)}={}){
 const url=new URL(href);
 if(!['http:','https:'].includes(url.protocol)||url.username||url.password)throw new Error('Unsupported external URL');
 let child;
 try{
  child=openWindow();
  if(child){child.opener=null;child.location.replace(url.href);return 'new-tab'}
 }catch{try{child?.close()}catch{}}
 navigate(url.href);return 'current-tab';
}
