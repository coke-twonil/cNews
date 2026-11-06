import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readMigratedStorage} from '../prototype/storage.mjs';

function store(entries){
 const values=new Map(entries);
 return {getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,v),values};
}
test('改名搬移原型資料，文章、已讀、訂閱及草稿原封不動',()=>{
 const data=JSON.stringify({version:1,threads:[{id:'thread',messages:[{id:'reply',read:false}]}],servers:[{subscriptions:['general.chat']}],draft:{body:'未完成草稿'}});
 const storage=store([['legacy',data]]);
 assert.equal(readMigratedStorage(storage,'current','legacy'),data);
 assert.equal(storage.getItem('current'),data);
 assert.equal(storage.getItem('legacy'),data);
});
test('已經有新名稱資料時唔會被舊分頁資料覆蓋',()=>{
 const storage=store([['legacy','older'],['current','newer']]);
 assert.equal(readMigratedStorage(storage,'current','legacy'),'newer');
});
test('搬移儲存失敗仍可讀舊資料；冇舊資料時唔建立空紀錄',()=>{
 const storage=store([['legacy','saved']]);storage.setItem=()=>{throw Error('quota')};
 assert.equal(readMigratedStorage(storage,'current','legacy'),'saved');
 const empty=store([]);assert.equal(readMigratedStorage(empty,'current','legacy'),null);assert.equal(empty.values.size,0);
});
