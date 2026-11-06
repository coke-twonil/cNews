import {swipeDirection} from './model.mjs';

// A trackpad burst survives replacement of the article DOM after navigation.
// Its momentum must not turn into a second swipe on the next message.
const wheelBurst={last:-Infinity,x:0,y:0,used:false};
export function bindArticleGestures(surface,{onSwipe,onIntent=()=>{},now=()=>performance.now(),wheel=wheelBurst}){
 if(!surface)return ()=>{};
 let pointer=null;
 const activeTouches=new Set(),listeners=[];
 const listen=(name,fn,options)=>{surface.addEventListener(name,fn,options);listeners.push([name,fn,options])};
 const clear=()=>{pointer=null;surface.classList.remove('swiping')};
 listen('pointerdown',e=>{
  if(e.pointerType==='touch')activeTouches.add(e.pointerId);
  if(!e.isPrimary||e.button!==0||activeTouches.size>1){clear();return}
  pointer={x:e.clientX,y:e.clientY,id:e.pointerId};
  // Capturing a link's tap here retargets its click to the surface,
  // cancelling native navigation. Capture links only after horizontal drag.
  if(!e.target?.closest?.('a[href],button,input,textarea,select,[contenteditable="true"]')){
   surface.setPointerCapture(e.pointerId);
   // Desktop text/image drag otherwise cancels the stream before up.
   if(e.pointerType==='mouse'&&e.cancelable)e.preventDefault();
  }
 });
 listen('pointermove',e=>{
  if(!pointer||pointer.id!==e.pointerId)return;
  const dx=e.clientX-pointer.x,dy=e.clientY-pointer.y;
  if(Math.abs(dx)>10&&Math.abs(dx)>Math.abs(dy)*1.7){
   surface.classList.add('swiping');
   if(e.cancelable)e.preventDefault();
   if(!surface.hasPointerCapture(e.pointerId))surface.setPointerCapture(e.pointerId);
  }
 });
 listen('pointerup',e=>{
  activeTouches.delete(e.pointerId);
  if(!pointer||pointer.id!==e.pointerId)return;
  const start=pointer;clear();
  const direction=swipeDirection(start,{x:e.clientX,y:e.clientY});
  if(direction){onIntent();onSwipe(direction)}
 });
 listen('pointercancel',e=>{activeTouches.delete(e.pointerId);clear()});
 listen('lostpointercapture',e=>{if(e.target===surface&&pointer?.id===e.pointerId)clear()});
 // Prevent native image/link drag from stealing the pointer stream.
 listen('dragstart',e=>e.preventDefault());
 listen('wheel',e=>{
  if(e.ctrlKey)return; // Keep browser pinch-to-zoom native.
  const time=now();
  if(time-wheel.last>240){wheel.x=0;wheel.y=0;wheel.used=false}
  wheel.last=time;
  const scale=e.deltaMode===1?16:e.deltaMode===2?surface.clientWidth:1;
  wheel.x+=e.deltaX*scale;wheel.y+=e.deltaY*scale;
  if(Math.abs(e.deltaX)>Math.abs(e.deltaY)*1.7&&e.cancelable)e.preventDefault();
  if(wheel.used)return;
  const direction=swipeDirection({x:0,y:0},{x:-wheel.x,y:wheel.y});
  if(direction){wheel.used=true;onIntent();onSwipe(direction)}
 },{passive:false});
 return ()=>{for(const [name,fn,options]of listeners)surface.removeEventListener(name,fn,options);clear()};
}
