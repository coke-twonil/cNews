import test from 'node:test';
import assert from 'node:assert/strict';
import {bindArticleGestures} from '../prototype/gestures.mjs';
class Surface{
 events=new Map();captured=new Set();clientWidth=390;classList={add(){},remove(){}};
 addEventListener(n,f){this.events.set(n,f)}removeEventListener(n){this.events.delete(n)}
 hasPointerCapture(id){return this.captured.has(id)}setPointerCapture(id){this.captured.add(id)}
 fire(n,values={}){const e={pointerId:1,pointerType:'mouse',isPrimary:true,button:0,clientX:0,clientY:0,deltaX:0,deltaY:0,deltaMode:0,cancelable:true,preventDefault(){this.prevented=true},...values};this.events.get(n)?.(e);return e}
}
function setup(wheel){const surface=new Surface(),moves=[];let time=0,intents=0;const dispose=bindArticleGestures(surface,{onSwipe:d=>moves.push(d),onIntent:()=>intents++,now:()=>time,...(wheel?{wheel}:{wheel:{last:-Infinity,x:0,y:0,used:false}})});return {surface,moves,dispose,advance:n=>time+=n,intents:()=>intents}}
test('mouse drag navigates both ways and captures pointer; tap and vertical scroll do not',()=>{
 const {surface:s,moves,intents}=setup();
 s.fire('pointerdown',{clientX:280});s.fire('pointermove',{clientX:100});assert.equal(s.hasPointerCapture(1),true);s.fire('pointerup',{clientX:100});
 s.fire('pointerdown',{clientX:100});s.fire('pointerup',{clientX:280});
 s.fire('pointerdown');s.fire('pointerup',{clientX:5});
 s.fire('pointerdown');s.fire('pointerup',{clientX:100,clientY:300});
 assert.deepEqual(moves,[1,-1]);assert.equal(intents(),2);
});
test('touch works once; cancelled and multi-touch gestures never navigate',()=>{
 const {surface:s,moves}=setup();
 s.fire('pointerdown',{pointerType:'touch',clientX:300});s.fire('pointerup',{pointerType:'touch',clientX:100});
 s.fire('pointerdown');s.fire('pointercancel');s.fire('pointerup',{clientX:200});
 s.fire('pointerdown',{pointerType:'touch'});s.fire('pointerdown',{pointerType:'touch',pointerId:2,isPrimary:false});s.fire('pointerup',{pointerType:'touch',clientX:200});
 assert.deepEqual(moves,[1]);
});
test('transferring implicit touch capture from a child does not cancel swipe',()=>{
 const {surface:s,moves}=setup();
 s.fire('pointerdown',{pointerType:'touch',clientX:300});
 s.fire('lostpointercapture',{target:{},pointerId:1});
 s.fire('pointerup',{pointerType:'touch',clientX:100});
 assert.deepEqual(moves,[1]);
});
test('trackpad accumulates one swipe per burst, including momentum across article replacement',()=>{
 const wheel={last:-Infinity,x:0,y:0,used:false},a=setup(wheel);
 a.surface.fire('wheel',{deltaX:45});a.advance(20);a.surface.fire('wheel',{deltaX:45});assert.deepEqual(a.moves,[1]);
 const b=setup(wheel);b.advance(40);b.surface.fire('wheel',{deltaX:120});assert.deepEqual(b.moves,[]);
 b.advance(300);b.surface.fire('wheel',{deltaX:-100});assert.deepEqual(b.moves,[-1]);
});
test('vertical wheel and pinch zoom stay native; cleanup removes bindings',()=>{
 const {surface:s,moves,dispose}=setup();
 assert.equal(s.fire('wheel',{deltaX:10,deltaY:200}).prevented,undefined);
 assert.equal(s.fire('wheel',{deltaX:300,ctrlKey:true}).prevented,undefined);
 assert.deepEqual(moves,[]);dispose();assert.equal(s.events.size,0);
});

test('link taps retain native navigation; only dragging a link captures and navigates',()=>{
 for(const pointerType of ['mouse','touch']){
  const {surface:s,moves,intents}=setup();
  const target={closest:selector=>selector.includes('a[href]')?{}:null};
  const down=s.fire('pointerdown',{pointerType,target,clientX:280});
  assert.equal(down.prevented,undefined);assert.equal(s.hasPointerCapture(1),false);
  s.fire('pointerup',{pointerType,target,clientX:278});
  assert.deepEqual(moves,[]);assert.equal(intents(),0);
  s.fire('pointerdown',{pointerType,target,clientX:280});
  s.fire('pointermove',{pointerType,target,clientX:100});
  assert.equal(s.hasPointerCapture(1),true);
  s.fire('pointerup',{pointerType,target,clientX:100});
  assert.deepEqual(moves,[1]);assert.equal(intents(),1);
 }
});
