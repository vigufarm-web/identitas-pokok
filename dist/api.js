const URL='https://pavgcpagdeyixafafxdi.supabase.co';
const KEY='sb_publishable_szoOlHYd2zaVc4ewDTxB6w_jXTLA8Pi';
const SESSION='vigu.identitas.session.v1';
async function call(path,{method='GET',token,body}={}){
 const response=await fetch(URL+path,{method,headers:{apikey:KEY,Authorization:'Bearer '+(token||KEY),'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(20000)});
 if(!response.ok){let msg='Permintaan belum berhasil ('+response.status+').';try{const x=await response.json();if(typeof x.message==='string'&&x.message.length<250)msg=x.message;}catch{}throw Object.assign(Error(msg),{status:response.status});}
 if(response.status===204)return null;const text=await response.text();return text?JSON.parse(text):null;
}
export function createApi(storage=localStorage){
 let session=null,refresh=null;try{session=JSON.parse(storage.getItem(SESSION)||'null');}catch{}
 function keep(value){session=value;storage.setItem(SESSION,JSON.stringify(value));}
 function saveTokens(result,identity=null){keep({access_token:result.access_token,refresh_token:result.refresh_token,expires_at:Math.floor(Date.now()/1000)+Number(result.expires_in||3600),identity:identity||session?.identity||null});}
 async function token(){
  if(!session?.refresh_token)throw Error('Masuk dengan akun petugas terlebih dahulu.');
  if(session.expires_at<=Date.now()/1000+60){
   if(!refresh){const old=session;refresh=(async()=>{const next=await call('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:{refresh_token:old.refresh_token}});if(session!==old)throw Error('Sesi telah berubah.');saveTokens(next);})();refresh.finally(()=>{refresh=null}).catch(()=>{});}
   await refresh;
  }
  return session.access_token;
 }
 async function member(t){const user=await call('/auth/v1/user',{token:t});if(!user?.id)throw Error('Identitas login tidak tersedia.');const list=await call('/rest/v1/marking_members?select=user_id,display_name,role,job,report_access,map_access,harvest_access&user_id=eq.'+encodeURIComponent(user.id),{token:t});if(!Array.isArray(list)||list.length!==1||!list[0].user_id)throw Error('Akun belum mendapat akses Marking.');const m=list[0];return {id:m.user_id,name:m.display_name,role:m.role,job:m.job,reportAccess:!!m.report_access,harvestAccess:!!m.harvest_access};}
 async function login(username,pin){
  const name=username.trim().toLowerCase();if(!name||!pin)throw Error('Isi username dan PIN.');
  const email=name.includes('@')?name:name+'@marking.vigufarm.invalid';
  const result=await call('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password:name.includes('@')?pin:'Marking-'+pin}});
  const identity=await member(result.access_token);saveTokens(result,identity);return identity;
 }
 async function verify(){const t=await token();const identity=await member(t);if(session.identity?.id&&session.identity.id!==identity.id)throw Error('Identitas akun berubah.');keep({...session,identity});return identity;}
 async function rpc(fn,body={}){const t=await token();return call('/rest/v1/rpc/'+fn,{method:'POST',token:t,body});}
 function logout(){session=null;storage.removeItem(SESSION);}
 return {login,verify,rpc,logout,identity:()=>session?.identity||null,hasSession:()=>!!session?.refresh_token};
}
