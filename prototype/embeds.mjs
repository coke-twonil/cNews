import {linkParts,renderLinks} from './links.mjs';

const escape=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const hostIs=(host,domain)=>host===domain||host==='www.'+domain||host==='m.'+domain||host==='mobile.'+domain;
const code='[A-Za-z0-9_-]+';

export function embedDescriptor(input){
 let u;try{u=new URL(input)}catch{return null}
 if(!['http:','https:'].includes(u.protocol)||u.username||u.password||u.port)return null;
 const h=u.hostname.toLowerCase(),p=u.pathname;let m;
 if(hostIs(h,'instagram.com')&&(m=p.match(new RegExp('^/(p|reel|reels)/('+code+')/?$'))))return {provider:'instagram',label:'Instagram',key:'instagram:'+m[2],url:`https://www.instagram.com/${m[1]==='p'?'p':'reel'}/${m[2]}/`};
 if((hostIs(h,'x.com')||hostIs(h,'twitter.com'))&&(m=p.match(/^\/(?:[A-Za-z0-9_]+\/status|i\/web\/status|i\/status)\/(\d+)\/?$/)))return {provider:'x',label:'X',key:'x:'+m[1],url:`https://twitter.com${p.replace(/\/$/,'')}`};
 if((hostIs(h,'threads.com')||hostIs(h,'threads.net'))&&(m=p.match(new RegExp('^/share/('+code+')/?$'))))return {provider:'threads',label:'Threads',key:'threads:share:'+m[1],url:`https://www.threads.com/share/${m[1]}`};
 if((hostIs(h,'threads.com')||hostIs(h,'threads.net'))&&(m=p.match(new RegExp('^/(?:@[^/]+/post|t)/('+code+')/?$'))))return {provider:'threads',label:'Threads',key:'threads:'+m[1],url:`https://www.threads.com/t/${m[1]}/`};
 if(hostIs(h,'facebook.com')&&(m=p.match(new RegExp('^/share/p/('+code+')/?$'))))return {provider:'facebook',label:'Facebook',key:'facebook:share:'+m[1],url:`https://www.facebook.com/share/p/${m[1]}/`};
 if(hostIs(h,'facebook.com')&&p==='/story.php'){
  const id=u.searchParams.get('id'),post=u.searchParams.get('story_fbid');
  if(/^\d+$/.test(id||'')&&/^[A-Za-z0-9_-]+$/.test(post||''))return {provider:'facebook',label:'Facebook',key:'facebook:'+post,url:`https://www.facebook.com/${id}/posts/${post}/`};
 }
 if(hostIs(h,'facebook.com')&&(m=p.match(/^\/(?:[A-Za-z0-9._-]+\/posts\/([A-Za-z0-9_-]+)|reel\/(\d+))\/?$/)))return {provider:'facebook',label:'Facebook',key:'facebook:'+(m[1]||m[2]),url:'https://www.facebook.com'+p};
 if(hostIs(h,'youtube.com')||h==='youtu.be'){
  const id=h==='youtu.be'?p.slice(1).split('/')[0]:p==='/watch'?u.searchParams.get('v'):p.match(/^\/(?:shorts|embed|live)\/([A-Za-z0-9_-]+)/)?.[1];
  if(id&&/^[A-Za-z0-9_-]{11}$/.test(id)){
   const raw=u.searchParams.get('t')||u.searchParams.get('start')||'';
   const parts=raw.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/);
   const start=/^\d+$/.test(raw)?Number(raw):parts?Number(parts[1]||0)*3600+Number(parts[2]||0)*60+Number(parts[3]||0):0;
   return {provider:'youtube',label:'YouTube',key:'youtube:'+id+':'+start,url:`https://www.youtube.com/watch?v=${id}${start?'&t='+start:''}`};
  }
 }
 if(hostIs(h,'tiktok.com')&&(m=p.match(/^\/@[A-Za-z0-9_.]+\/(?:video|photo)\/(\d{8,30})\/?$/)))return {provider:'tiktok',label:'TikTok',key:'tiktok:'+m[1],url:'https://www.tiktok.com'+p};
 if((h==='vimeo.com'||h==='www.vimeo.com')&&(m=p.match(/^\/(\d+)(?:\/([A-Za-z0-9]+))?\/?$/)))return {provider:'vimeo',label:'Vimeo',key:'vimeo:'+m[1]+':'+(m[2]||''),url:`https://vimeo.com/${m[1]}${m[2]?'/'+m[2]:''}`};
 if(h==='open.spotify.com'&&(m=p.match(/^\/(?:intl-[a-z-]+\/)?(track|album|playlist|episode|show|artist)\/([A-Za-z0-9]{22})\/?$/)))return {provider:'spotify',label:'Spotify',key:`spotify:${m[1]}:${m[2]}`,url:`https://open.spotify.com/${m[1]}/${m[2]}`};
 return null;
}

export function renderMediaLinks(text,seen=new Set()){
 return linkParts(text).map(part=>{
  if(!part.href)return renderLinks(part.text);
  const link=`<a href="${escape(part.href)}" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer">${escape(part.text)}</a>`;
  const embed=embedDescriptor(part.href);
  if(!embed||seen.has(embed.key))return link;
  seen.add(embed.key);
  return link+`<span class="media-embed" data-embed-url="${escape(embed.url)}" data-embed-label="${embed.label}" data-state="waiting"><span class="embed-status" role="status">${embed.label} · 等待載入…</span><span class="embed-slot"></span></span>`;
 }).join('');
}

export function mountEmbeds(container){
 if(!container)return ()=>{};
 const cards=[...container.querySelectorAll('.media-embed')],active=new Map();
 const origin=new URL(location.origin);origin.port='8766';
 let disposed=false;
 const observer=typeof IntersectionObserver!=='undefined'?new IntersectionObserver(entries=>{
  for(const entry of entries)if(entry.isIntersecting){observer.unobserve(entry.target);load(entry.target)}
 },{root:document.getElementById('article-scroll'),rootMargin:'250px'}):null;
 function fail(card,frame){
  if(disposed||!card.isConnected)return;
  frame?.remove();card.dataset.state='error';
  const status=card.querySelector('.embed-status');status.textContent=`未能內嵌 ${card.dataset.embedLabel}，可點上面連結開啟。`;
  if(!card.querySelector('.embed-retry')){
   const retry=document.createElement('button');retry.type='button';retry.className='embed-retry';retry.textContent='重試';
   retry.addEventListener('click',()=>{retry.remove();load(card)});status.append(' ',retry);
  }
 }
 function load(card){
  if(disposed||!card.isConnected)return;
  card.dataset.state='loading';card.querySelector('.embed-status').textContent=`${card.dataset.embedLabel} · 載入中…`;
  const frame=document.createElement('iframe'),token=crypto.randomUUID();
  const src=new URL('/embed',origin);src.searchParams.set('url',card.dataset.embedUrl);src.searchParams.set('origin',location.origin);src.searchParams.set('token',token);src.searchParams.set('width',String(Math.round(card.getBoundingClientRect().width)));
  frame.title=card.dataset.embedLabel+' embedded content';frame.src=src.href;
  // This service has its own origin/port and no reader data. Never give
  // third-party scripts a same-origin window into the reader/localStorage.
  frame.setAttribute('sandbox','allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox allow-presentation');
  frame.allow='fullscreen; encrypted-media; picture-in-picture';frame.referrerPolicy='no-referrer';
  frame.style.height='280px';card.querySelector('.embed-slot').replaceChildren(frame);
  const timer=setTimeout(()=>{active.delete(token);fail(card,frame)},25000);
  active.set(token,{card,frame,timer});
  frame.addEventListener('error',()=>{clearTimeout(timer);active.delete(token);fail(card,frame)},{once:true});
 }
 function message(event){
  if(event.origin!==origin.origin||event.data?.type!=='cnews-embed')return;
  const entry=active.get(event.data.token);
  if(!entry||event.source!==entry.frame.contentWindow)return;
  const {card,frame,timer}=entry;
  if(event.data.status==='error'){clearTimeout(timer);active.delete(event.data.token);fail(card,frame);return}
  if(event.data.status==='ready'){
   clearTimeout(timer);card.dataset.state='ready';card.querySelector('.embed-status').textContent='';
  }
  const height=Number(event.data.height);
  if(Number.isFinite(height)&&height>=100&&height<=1800)frame.style.height=Math.ceil(height)+'px';
 }
 window.addEventListener('message',message);
 for(const card of cards)observer?observer.observe(card):load(card);
 return ()=>{disposed=true;observer?.disconnect();window.removeEventListener('message',message);for(const entry of active.values())clearTimeout(entry.timer);active.clear()};
}
