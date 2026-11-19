// Data yang belum diterima server dipisahkan menurut identitas petugas.
export async function openLocal(indexedDBImpl=globalThis.indexedDB){
 if(!indexedDBImpl)throw Error('Penyimpanan offline tidak tersedia pada browser ini.');
 const request=indexedDBImpl.open('vigu-identitas-pokok-v1',1);
 request.onupgradeneeded=()=>{const db=request.result;const queue=db.createObjectStore('queue',{keyPath:'seq',autoIncrement:true});queue.createIndex('id','id',{unique:true});db.createObjectStore('trees',{keyPath:'code'});db.createObjectStore('meta',{keyPath:'key'});};
 return new Promise((resolve,reject)=>{request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});
}
function transaction(db,stores,mode,run){return new Promise((resolve,reject)=>{const tx=db.transaction(stores,mode);let result;try{result=run(tx);}catch(e){tx.abort();reject(e);return;}tx.oncomplete=()=>resolve(result?.result);tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error||Error('Penyimpanan dibatalkan.'));});}
export async function putMeta(db,key,value){return transaction(db,['meta'],'readwrite',tx=>tx.objectStore('meta').put({key,value}));}
export async function getMeta(db,key){const row=await transaction(db,['meta'],'readonly',tx=>tx.objectStore('meta').get(key));return row?.value;}
export async function cacheTree(db,tree){return transaction(db,['trees'],'readwrite',tx=>tx.objectStore('trees').put(tree));}
export async function cachedTree(db,code){return transaction(db,['trees'],'readonly',tx=>tx.objectStore('trees').get(code));}
export async function enqueue(db,actor,event,tree=null){
 if(!actor||!event?.id||!event.code)throw Error('Identitas petugas dan pencatatan wajib tersedia.');
 const existing=await transaction(db,['queue'],'readonly',tx=>tx.objectStore('queue').index('id').get(event.id));
 if(existing){if(existing.actor!==actor||JSON.stringify(existing.event)!==JSON.stringify(event))throw Error('ID pencatatan sudah dipakai.');return;}
 return transaction(db,['queue','trees'],'readwrite',tx=>{if(tree)tx.objectStore('trees').put(tree);return tx.objectStore('queue').add({id:event.id,actor,event,createdAt:Date.now(),status:'pending'});});
}
export async function pending(db,actor){const all=await transaction(db,['queue'],'readonly',tx=>tx.objectStore('queue').getAll());return all.filter(x=>x.actor===actor).sort((a,b)=>a.seq-b.seq);}
export async function syncQueue(db,actor,send){
 const rows=await pending(db,actor),blocked=new Set();let synced=0;
 for(const item of rows){
  if(blocked.has(item.event.code))continue;
  if(item.status==='periksa'){blocked.add(item.event.code);continue;}
  try{
   const result=await send(item.event);
   if(!result||result.code!==item.event.code)throw Error('Server belum mengonfirmasi pokok yang benar.');
   await transaction(db,['queue','trees'],'readwrite',tx=>{tx.objectStore('trees').put(result);return tx.objectStore('queue').delete(item.seq);});synced++;
  }catch(error){
   blocked.add(item.event.code);
   if(error?.status===400||error?.status===409){item.status='periksa';item.message=String(error.message||'Data perlu diperiksa.').slice(0,300);await transaction(db,['queue'],'readwrite',tx=>tx.objectStore('queue').put(item));continue;}
   return {synced,remaining:(await pending(db,actor)).length,error:error.message};
  }
 }
 return {synced,remaining:(await pending(db,actor)).length};
}
