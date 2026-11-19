export const COLORS=[['BK','Black','#111111'],['GN','Green','#56a536'],['YW','Yellow','#e8d600'],['WE','White','#ffffff'],['RD','Red','#f11218'],['PE','Purple','#a429ee'],['PK','Pink','#ff59dd'],['OE','Orange','#ff9028'],['BN','Brown','#964818'],['TA','Tosca','#05ccaa']];
export const PHASES=['PC','R1','R2','R3','R4'];
const CODE_RE=/^IP1:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}):(\d{1,7})$/i;
export function makeCode(batchId,serial){
 if(!Number.isSafeInteger(serial)||serial<1||serial>2000000)throw Error('Nomor label tidak valid.');
 const code=`IP1:${batchId}:${serial}`;
 if(!CODE_RE.test(code))throw Error('Identitas batch tidak valid.');return code;
}
export function parseCode(value){
 const match=String(value||'').trim().match(CODE_RE);if(!match)throw Error('Kode bukan label Identitas Pokok.');
 const serial=Number(match[2]);if(serial<1||serial>2000000)throw Error('Nomor label tidak valid.');
 return {batchId:match[1].toLowerCase(),serial,code:makeCode(match[1].toLowerCase(),serial)};
}
export function derive(tree,event){
 if(!event?.id||!event.code||!event.type)throw Error('Data pencatatan belum lengkap.');
 if(event.type==='register'){
  if(tree)throw Error('Barcode sudah terdaftar.');parseCode(event.code);
  if(!event.block?.trim()||!event.row?.trim()||!PHASES.includes(event.phase))throw Error('Blok, baris, dan fase awal wajib diisi.');
  if(!Number.isFinite(event.lat)||!Number.isFinite(event.lng)||Math.abs(event.lat)>90||Math.abs(event.lng)>180)throw Error('Posisi GPS tidak valid.');
  return {code:event.code,block:event.block.trim(),row:event.row.trim(),phase:event.phase,condition:'hidup',color:null,awaiting:false,version:1,lat:event.lat,lng:event.lng};
 }
 if(!tree)throw Error('Barcode belum terdaftar.');
 if(tree.version!==event.expectedVersion)throw Error('Data sudah berubah di perangkat lain; periksa sebelum melanjutkan.');
 if(event.type==='census'){
  if(!['hidup','mati','lainnya'].includes(event.condition))throw Error('Pilih kondisi pokok.');
  if(event.condition==='lainnya'&&!event.note?.trim())throw Error('Isi keterangan kondisi lainnya.');
  if(event.color&&!COLORS.some(c=>c[0]===event.color))throw Error('Warna pita tidak valid.');
  return {...tree,condition:event.condition,note:event.note?.trim()||'',color:event.color||null,version:tree.version+1};
 }
 if(event.type==='harvest'){
  if(tree.awaiting||tree.condition==='mati')throw Error('Pokok belum siap dikonfirmasi panen.');
  if(event.phase!==tree.phase)throw Error('Fase berubah; periksa ulang sebelum panen.');
  if(!tree.color)throw Error('Catat warna pita sebelum panen.');
  const next=PHASES.indexOf(tree.phase),wait=tree.phase==='R3'||tree.phase==='R4';
  if(next<0)throw Error('Fase pokok tidak dikenali.');
  return {...tree,phase:wait?tree.phase:PHASES[next+1],awaiting:wait,lastHarvest:{phase:tree.phase,color:tree.color,date:event.date},color:null,version:tree.version+1};
 }
 if(event.type==='decision'){
  if(!tree.awaiting||event.role!=='admin')throw Error('Keputusan fase hanya dapat dilakukan admin.');
  if(event.action==='r4'&&tree.phase!=='R3')throw Error('R4 hanya dapat dipilih setelah panen R3.');
  if(!['r4','tanam_ulang'].includes(event.action))throw Error('Pilihan fase tidak valid.');
  return {...tree,phase:event.action==='r4'?'R4':'PC',awaiting:false,version:tree.version+1};
 }
 throw Error('Jenis pencatatan tidak dikenal.');
}
