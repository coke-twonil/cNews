// Keep the pre-rename data readable without replacing a newer data store.
export function readMigratedStorage(storage,key,legacyKey){
 const current=storage.getItem(key);
 if(current!==null)return current;
 const legacy=storage.getItem(legacyKey);
 if(legacy!==null){
  try{storage.setItem(key,legacy)}catch{/* Read the old data even if copying fails. */}
 }
 return legacy;
}
