import {test} from 'node:test';
import assert from 'node:assert/strict';
import {linkParts,renderLinks} from '../prototype/links.mjs';

test('Facebook、Instagram、Threads、連登及其他網站保留原有目的地',()=>{
 const urls=['https://www.facebook.com/example/posts/123?x=1&y=2#comments','https://www.instagram.com/p/example/','https://www.threads.net/@example/post/123','https://www.threads.com/@example/post/123','https://lihkg.com/thread/1234567/page/1','https://example.com/other'];
 const source=urls.join('\n');
 assert.deepEqual(linkParts(source).filter(p=>p.href).map(p=>p.href),urls);
 assert.equal(linkParts(source).map(p=>p.text).join(''),source);
});
test('識別正文及引用內網址，中文標點唔會變成 URL 一部分',()=>{
 const text='睇下：https://lihkg.com/thread/123/page/1。\n> IG：https://www.instagram.com/p/abc/，仲有 www.facebook.com/example！';
 const parts=linkParts(text);
 assert.deepEqual(parts.filter(p=>p.href).map(p=>p.href),['https://lihkg.com/thread/123/page/1','https://www.instagram.com/p/abc/','https://www.facebook.com/example']);
 assert.equal(parts.map(p=>p.text).join(''),text);
});
test('保留平衡括號、query、fragment 及 Unicode path，剔除句末括號',()=>{
 const text='(https://example.com/a_(b)?x=1&y=2#section). https://example.com/中文。';
 const urls=linkParts(text).filter(p=>p.href);
 assert.equal(urls[0].href,'https://example.com/a_(b)?x=1&y=2#section');
 assert.equal(urls[1].href,'https://example.com/%E4%B8%AD%E6%96%87');
 assert.equal(linkParts(text).map(p=>p.text).join(''),text);
});
test('非 HTTP(S) scheme、帶 userinfo 或無效網址唔產生連結',()=>{
 const text='javascript:alert(1) file:///private/test data:text/html,test https://user:pass@example.com/ https://';
 assert.equal(linkParts(text).filter(p=>p.href).length,0);
});
test('文章 HTML 安全轉義，外部連結開新頁並保留閱讀位置',()=>{
 const html=renderLinks('<img src=x onerror=alert(1)> https://example.com/?x=1&y=2');
 assert.ok(html.startsWith('&lt;img'));
 assert.equal(html.includes('<img'),false);
 assert.ok(html.includes('href="https://example.com/?x=1&amp;y=2"'));
 assert.ok(html.includes('target="_blank"'));
 assert.ok(html.includes('rel="noopener noreferrer"'));
});

test('external opening isolates the new tab and falls back when popups are unavailable',async()=>{
 const {openExternalLink}=await import('../prototype/links.mjs');
 const href='https://www.facebook.com/share/p/1LLk5pK1q8/?mibextid=wwXIfr';
 const navigations=[],opened=[];
 const child={opener:'reader',location:{replace:url=>opened.push(url)}};
 assert.equal(openExternalLink(href,{openWindow:()=>child,navigate:url=>navigations.push(url)}),'new-tab');
 assert.equal(child.opener,null);assert.deepEqual(opened,[href]);assert.deepEqual(navigations,[]);
 for(const openWindow of [()=>null,()=>{throw new Error('blocked')}]){
  assert.equal(openExternalLink(href,{openWindow,navigate:url=>navigations.push(url)}),'current-tab');
 }
 assert.deepEqual(navigations,[href,href]);
 assert.throws(()=>openExternalLink('javascript:alert(1)'));
});
