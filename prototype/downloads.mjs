export function downloadInventory(numbers,knownNumbers=[],cursor=0,older=false){
 const known=new Set(knownNumbers);
 const highWater=knownNumbers.reduce((max,n)=>Math.max(max,n),cursor||0);
 const available=[...new Set(numbers)].filter(n=>Number.isSafeInteger(n)&&n>0).sort((a,b)=>a-b);
 return {highWater,pending:available.filter(n=>!known.has(n)&&(older?n<=highWater:n>highWater)),olderCount:available.filter(n=>!known.has(n)&&n<=highWater).length};
}
export function chooseNumbers(pending,count=500,order='next'){
 const limit=count==='all'?pending.length:Math.max(1,Math.min(pending.length,Number(count)||500));
 return order==='latest'?pending.slice(-limit):pending.slice(0,limit);
}
export function batches(numbers,size=500){const result=[];for(let i=0;i<numbers.length;i+=size)result.push(numbers.slice(i,i+size));return result}
