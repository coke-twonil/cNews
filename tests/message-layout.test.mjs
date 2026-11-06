import test from 'node:test';
import assert from 'node:assert/strict';
import {splitHistory,combineHistory,articleSections} from '../prototype/message-layout.mjs';
test('new text stays before images, attribution and nested history stay after images',()=>{
 const body='新內容\n\nOn 15:00 05/11, Parent wrote:\n> 父訊息\n>> 祖父訊息';
 const split=splitHistory(body);assert.equal(split.text,'新內容\n\n');assert.ok(split.history.startsWith('On 15:00'));
 const parts=articleSections({body,images:['one','two']});
 assert.deepEqual(parts.map(p=>p.type),['text','image','image','text']);
 assert.equal(parts[0].text,'新內容\n\n');assert.ok(parts[3].text.includes('>> 祖父訊息'));
 assert.equal(combineHistory('新內容',split.history),body);
});
test('ordered MIME parts and legacy text-before-attachment both put images before history',()=>{
 for(const contentParts of [[{type:'text',text:'新內容'},{type:'image',index:0},{type:'text',text:'On now, A wrote:\n> History'}],[{type:'text',text:'新內容\nOn now, A wrote:\n> History'},{type:'image',index:0}]]){
  assert.deepEqual(articleSections({contentParts,images:['photo']}).map(p=>p.type),['text','image','text']);
 }
 assert.equal(splitHistory('On weekdays I wrote: notes without quote').history,'');
 assert.equal(splitHistory('> 原文').history,'> 原文');
});
