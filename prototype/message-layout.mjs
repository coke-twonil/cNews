// Keep the attribution with its quoted parent history.
export function splitHistory(body){
 const text=String(body||'');
 const match=/^(?:On [^\r\n]+ wrote:[ \t]*\r?\n(?=(?:[ \t]*\r?\n)*[ \t]*>)|[ \t]*>)/m.exec(text);
 return match?{text:text.slice(0,match.index),history:text.slice(match.index)}:{text,history:''};
}
export function combineHistory(text,history){return history?`${text.trimEnd()}\n\n${history}`:text}
export function articleSections(message){
 const parts=message.contentParts||[{type:'text',text:message.body||''},...(message.images||[]).map((_,index)=>({type:'image',index}))];
 const main=[],history=[];
 for(const part of parts){
  if(part.type==='image'){if(message.images?.[part.index])main.push(part);continue}
  if(part.type!=='text')continue;
  const split=splitHistory(part.text);
  if(split.text)main.push({type:'text',text:split.text});
  if(split.history)history.push({type:'text',text:split.history});
 }
 return [...main,...history];
}
