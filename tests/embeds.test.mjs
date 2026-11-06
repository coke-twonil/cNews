import {test} from 'node:test';
import assert from 'node:assert/strict';
import {embedDescriptor,renderMediaLinks} from '../prototype/embeds.mjs';

test('八個平台只識別可嵌入嘅貼文／媒體 URL',()=>{
 const cases=[
  ['https://www.instagram.com/p/fA9uwTtkSN/','instagram'],
  ['https://www.instagram.com/reel/AbCd_123/','instagram'],
  ['https://x.com/TwitterDev/status/1354143047324299264','x'],
  ['https://twitter.com/i/web/status/1354143047324299264','x'],
  ['https://www.threads.net/@threads/post/DWjTI0cgH5O/','threads'],
  ['https://www.threads.com/t/DWjTI0cgH5O/','threads'],
  ['https://www.facebook.com/example/posts/pfbid123/','facebook'],
  ['https://www.facebook.com/reel/123456789/','facebook'],
  ['https://youtu.be/M7lc1UVf-VE','youtube'],
  ['https://www.youtube.com/shorts/M7lc1UVf-VE','youtube'],
  ['https://www.tiktok.com/@scout2015/video/6718335390845095173','tiktok'],
  ['https://vimeo.com/76979871','vimeo'],
  ['https://open.spotify.com/track/0Lr4kGOYn9l83EjuK6cZFQ','spotify']
 ];
 for(const [url,provider]of cases)assert.equal(embedDescriptor(url)?.provider,provider,url);
});
test('唔將首頁、未知網站、偽裝域名、userinfo 或非 HTTP(S) 當成 embed',()=>{
 for(const url of ['https://instagram.com/','https://x.com/home','https://lihkg.com/thread/123/page/1','https://instagram.com.evil.test/p/abc/','https://user@instagram.com/p/abc/','https://instagram.com:8765/p/abc/','javascript:alert(1)','https://youtu.be/invalid'])assert.equal(embedDescriptor(url),null,url);
});
test('YouTube 時間戳、Vimeo 私人 hash 同 Spotify 內容 ID 會保留',()=>{
 assert.equal(embedDescriptor('https://youtu.be/M7lc1UVf-VE?t=1m20s').url,'https://www.youtube.com/watch?v=M7lc1UVf-VE&t=80');
 assert.ok(embedDescriptor('https://vimeo.com/76979871/abc123').url.endsWith('/abc123'));
 assert.ok(embedDescriptor('https://open.spotify.com/intl-zh/episode/0Lr4kGOYn9l83EjuK6cZFQ').url.includes('/episode/'));
});
test('同一篇被引用多次只建立一個 embed，但保留每條原連結',()=>{
 const seen=new Set();
 const body=renderMediaLinks('https://x.com/TwitterDev/status/1354143047324299264',seen);
 const quote=renderMediaLinks('https://twitter.com/i/web/status/1354143047324299264',seen);
 assert.equal((body+quote).match(/class="media-embed"/g).length,1);
 assert.equal((body+quote).match(/<a /g).length,2);
});
test('X 保留有作者嘅原始路徑，避免轉成 oEmbed 不接受嘅 i/web URL',()=>{
 assert.equal(embedDescriptor('https://x.com/TwitterDev/status/1354143047324299264').url,'https://twitter.com/TwitterDev/status/1354143047324299264');
});
test('載入前／失敗時仍有原網址，唔插入任意文章 HTML',()=>{
 const html=renderMediaLinks('<script>alert(1)</script> https://www.instagram.com/p/abc/');
 assert.ok(html.includes('&lt;script&gt;'));
 assert.equal(html.includes('<script>'),false);
 assert.ok(html.includes('href="https://www.instagram.com/p/abc/"'));
 assert.ok(html.includes('data-state="waiting"'));
 assert.equal(renderMediaLinks('https://example.com/').includes('media-embed'),false);
});
test('Threads share 短網址亦建立 embed，原連結保留',()=>{
 const url='https://www.threads.com/share/BAVHcta3-N';
 assert.equal(embedDescriptor(url).provider,'threads');
 const html=renderMediaLinks(url);assert.ok(html.includes('media-embed'));assert.ok(html.includes(`href="${url}"`));
 for(const bad of ['https://threads.com.evil.test/share/abc','https://threads.com/share/abc/extra'])assert.equal(embedDescriptor(bad),null);
});
test('Facebook share/p and story permalinks embed without losing the original link',()=>{
 const shared='https://www.facebook.com/share/p/1LLk5pK1q8/?mibextid=wwXIfr';
 assert.equal(embedDescriptor(shared).provider,'facebook');
 assert.ok(renderMediaLinks(shared).includes('class="media-embed"'));
 assert.ok(renderMediaLinks(shared).includes('mibextid=wwXIfr'));
 assert.equal(embedDescriptor('https://www.facebook.com/story.php?story_fbid=1671629630999953&id=100044587952620').url,'https://www.facebook.com/100044587952620/posts/1671629630999953/');
 assert.equal(embedDescriptor('https://www.facebook.com/story.php?id=abc&story_fbid=123'),null);
 assert.equal(embedDescriptor('https://facebook.com.evil.test/share/p/abc/'),null);
});
