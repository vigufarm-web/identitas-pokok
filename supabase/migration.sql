-- Belum diterapkan: jalankan hanya setelah pemeriksaan hak dan uji transaksi.
begin;
create table if not exists public.ip_label_batches (
 id uuid primary key, quantity integer not null check(quantity between 1 and 2000000),
 created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.ip_trees (
 code text primary key, block text not null, row_label text not null,
 lat double precision not null, lng double precision not null, accuracy double precision,
 phase text not null check(phase in ('PC','R1','R2','R3','R4')),
 condition text not null check(condition in ('belum_sensus','hidup','mati','lainnya')),
 note text not null default '', color text, awaiting_decision boolean not null default false,
 version integer not null default 1 check(version>0), created_at timestamptz not null default now(),
 constraint ip_valid_position check(lat between -90 and 90 and lng between -180 and 180)
);
create index if not exists ip_trees_block_idx on public.ip_trees(block);
create index if not exists ip_trees_block_position_idx on public.ip_trees(block,lat,lng);
create table if not exists public.ip_census_sessions (
 id uuid primary key, block text not null, state text not null default 'open' check(state in ('open','applied')),
 created_by uuid, created_at timestamptz not null default now(), applied_by uuid, applied_at timestamptz
);
create unique index if not exists ip_one_open_census_per_block on public.ip_census_sessions(block) where state='open';
create table if not exists public.ip_events (
 id uuid primary key, tree_code text not null references public.ip_trees(code), actor uuid not null,
 event_type text not null, payload jsonb not null, result jsonb not null, created_at timestamptz not null default now()
);
create index if not exists ip_events_tree_idx on public.ip_events(tree_code,created_at);
create table if not exists public.ip_census_entries (
 session_id uuid not null references public.ip_census_sessions(id), tree_code text not null references public.ip_trees(code),
 event_id uuid not null references public.ip_events(id), expected_version integer not null,
 condition text not null, note text not null default '', color text, primary key(session_id,tree_code)
);
alter table public.ip_label_batches enable row level security;
alter table public.ip_trees enable row level security;
alter table public.ip_census_sessions enable row level security;
alter table public.ip_events enable row level security;
alter table public.ip_census_entries enable row level security;
revoke all on public.ip_label_batches,public.ip_trees,public.ip_census_sessions,public.ip_events,public.ip_census_entries from public,anon,authenticated;

create or replace function public.ip_member_allowed(p_write boolean default false,p_admin boolean default false)
returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.marking_members m where m.user_id=auth.uid() and m.active=true
  and (not p_admin or m.role='admin') and (not p_write or m.role='admin' or m.job='sensus'));
$$;
revoke all on function public.ip_member_allowed(boolean,boolean) from public,anon,authenticated;

create or replace function public.ip_make_batch(p_id uuid,p_quantity integer)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare existing public.ip_label_batches%rowtype;
begin
 if not public.ip_member_allowed(true,true) then raise exception 'Hanya admin dapat membuat label'; end if;
 if p_id is null or p_quantity not between 1 and 2000000 then raise exception 'Jumlah label tidak valid'; end if;
 insert into public.ip_label_batches(id,quantity,created_by) values(p_id,p_quantity,auth.uid()) on conflict(id) do nothing;
 select * into existing from public.ip_label_batches where id=p_id;
 if existing.created_by<>auth.uid() or existing.quantity<>p_quantity then raise exception 'Batch sudah ada dengan isi berbeda'; end if;
 return jsonb_build_object('id',existing.id,'quantity',existing.quantity);
end $$;
revoke all on function public.ip_make_batch(uuid,integer) from public,anon;
grant execute on function public.ip_make_batch(uuid,integer) to authenticated;

create or replace function public.ip_start_session(p_id uuid,p_block text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare result public.ip_census_sessions%rowtype;
begin
 if not public.ip_member_allowed(true,false) then raise exception 'Akun tidak memiliki hak sensus'; end if;
 if p_id is null or length(trim(coalesce(p_block,''))) not between 1 and 80 then raise exception 'Blok wajib diisi'; end if;
 if not exists(select 1 from public.marking_boundaries b cross join lateral jsonb_array_elements(b.geojson->'features') f where b.id='active' and trim(coalesce(f->'properties'->>'Nama_Blok',f->'properties'->>'NAMA_BLOK',f->'properties'->>'nama_blok',f->'properties'->>'BLOK',f->'properties'->>'Blok',f->'properties'->>'blok',f->'properties'->>'name',f->'properties'->>'Nama',''))=trim(p_block)) then raise exception 'Blok tidak ada pada peta GIS'; end if;
 insert into public.ip_census_sessions(id,block,created_by) values(p_id,trim(p_block),auth.uid()) on conflict do nothing;
 select * into result from public.ip_census_sessions where block=trim(p_block) and state='open';
 if not found then raise exception 'Sesi tidak dapat dibuka'; end if;
 return to_jsonb(result);
end $$;
revoke all on function public.ip_start_session(uuid,text) from public,anon;
grant execute on function public.ip_start_session(uuid,text) to authenticated;

create or replace function public.ip_apply_session(p_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s public.ip_census_sessions%rowtype; n integer;
begin
 if not public.ip_member_allowed(true,false) then raise exception 'Akun tidak memiliki hak sensus'; end if;
 select * into s from public.ip_census_sessions where id=p_id for update;
 if not found then raise exception 'Sesi tidak ditemukan'; end if;
 if s.state='applied' then return jsonb_build_object('state','applied','id',p_id); end if;
 perform t.code from public.ip_trees t join public.ip_census_entries e on e.tree_code=t.code where e.session_id=p_id order by t.code for update of t;
 if exists(select 1 from public.ip_census_entries e join public.ip_trees t on t.code=e.tree_code where e.session_id=p_id and t.version<>e.expected_version) then raise exception 'Ada pokok berubah setelah sensus; periksa sebelum menerapkan'; end if;
 update public.ip_trees t set condition=e.condition,note=e.note,color=e.color,version=t.version+1
 from public.ip_census_entries e where e.session_id=p_id and e.tree_code=t.code;
 get diagnostics n = row_count;
 if n=0 then raise exception 'Sesi belum memiliki hasil'; end if;
 update public.ip_census_sessions set state='applied',applied_by=auth.uid(),applied_at=clock_timestamp() where id=p_id;
 return jsonb_build_object('state','applied','id',p_id,'count',n);
end $$;
revoke all on function public.ip_apply_session(uuid) from public,anon;
grant execute on function public.ip_apply_session(uuid) to authenticated;

create or replace function public.ip_apply_event(p_event jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare ev_id uuid; v_code text; typ text; current_tree public.ip_trees%rowtype; previous public.ip_events%rowtype;
 batch_id uuid; serial integer; qty integer; event_date date; sess uuid; result jsonb; state_next text; wait_next boolean;
begin
 if not public.ip_member_allowed(false,false) then raise exception 'Akun tidak memiliki akses'; end if;
 if p_event is null or pg_column_size(p_event)>8192 then raise exception 'Pencatatan tidak valid'; end if;
 ev_id:=(p_event->>'id')::uuid;v_code:=p_event->>'code';typ:=p_event->>'type';
 if ev_id is null or v_code !~ '^IP1:[0-9a-f-]{36}:[1-9][0-9]{0,6}$' or typ not in ('register','census','harvest','decision') then raise exception 'Identitas atau jenis pencatatan tidak valid'; end if;
 if typ in ('register','census') and not public.ip_member_allowed(true,false) then raise exception 'Akun tidak memiliki hak sensus'; end if;
 if typ='harvest' and not exists(select 1 from public.marking_members m where m.user_id=auth.uid() and m.active=true and (m.role='admin' or m.harvest_access=true)) then raise exception 'Akun tidak memiliki hak panen'; end if;
 if typ='decision' and not public.ip_member_allowed(true,true) then raise exception 'Keputusan fase hanya oleh admin'; end if;
 perform pg_advisory_xact_lock(hashtextextended('ip-tree:'||v_code,0));
 select * into previous from public.ip_events where id=ev_id;
 if found then
  if previous.actor<>auth.uid() or previous.payload<>p_event then raise exception 'ID pencatatan sudah dipakai'; end if;
  return previous.result;
 end if;
 if typ='census' then
  sess:=(p_event->>'sessionId')::uuid;
  perform 1 from public.ip_census_sessions where id=sess and state='open' for update;
  if not found then raise exception 'Sesi sensus tidak terbuka'; end if;
 end if;
 select * into current_tree from public.ip_trees where ip_trees.code=v_code for update;
 if typ='register' then
  if found then raise exception 'Barcode sudah terdaftar; sinkronkan dan periksa'; end if;
  batch_id:=split_part(v_code,':',2)::uuid;serial:=split_part(v_code,':',3)::integer;
  select quantity into qty from public.ip_label_batches where id=batch_id;
  if qty is null or serial>qty then raise exception 'Barcode belum diterbitkan admin'; end if;
  if length(trim(coalesce(p_event->>'block',''))) not between 1 and 80 or length(trim(coalesce(p_event->>'row',''))) not between 1 and 40 or p_event->>'phase' not in ('PC','R1','R2','R3','R4') then raise exception 'Blok, baris, dan fase awal wajib diisi'; end if;
  if not exists(select 1 from public.marking_boundaries b cross join lateral jsonb_array_elements(b.geojson->'features') f where b.id='active' and trim(coalesce(f->'properties'->>'Nama_Blok',f->'properties'->>'NAMA_BLOK',f->'properties'->>'nama_blok',f->'properties'->>'BLOK',f->'properties'->>'Blok',f->'properties'->>'blok',f->'properties'->>'name',f->'properties'->>'Nama',''))=trim(p_event->>'block')) then raise exception 'Blok tidak ada pada peta GIS'; end if;
  insert into public.ip_trees(code,block,row_label,lat,lng,accuracy,phase,condition)
  values(v_code,trim(p_event->>'block'),trim(p_event->>'row'),(p_event->>'lat')::float8,(p_event->>'lng')::float8,nullif(p_event->>'accuracy','')::float8,p_event->>'phase','belum_sensus') returning * into current_tree;
 else
  if not found then raise exception 'Barcode belum terdaftar'; end if;
  if (p_event->>'expectedVersion')::integer is distinct from current_tree.version then raise exception 'Data pokok berubah; sinkronkan dan periksa'; end if;
  if typ='census' then
   if p_event->>'condition' not in ('hidup','mati','lainnya') or (p_event->>'condition'='lainnya' and length(trim(coalesce(p_event->>'note','')))=0) then raise exception 'Kondisi tidak valid'; end if;
   if coalesce(p_event->>'color','')<>'' and p_event->>'color' not in ('BK','GN','YW','WE','RD','PE','PK','OE','BN','TA') then raise exception 'Warna tidak valid'; end if;
   if not exists(select 1 from public.ip_census_sessions where id=sess and block=current_tree.block and state='open') then raise exception 'Sesi sensus tidak terbuka untuk blok ini'; end if;
   if exists(select 1 from public.ip_census_entries where session_id=sess and tree_code=v_code) then raise exception 'Pokok sudah tercatat pada sesi sensus ini'; end if;
  elsif typ='harvest' then
   if current_tree.awaiting_decision or current_tree.condition<>'hidup' or current_tree.color is null or p_event->>'phase' is distinct from current_tree.phase then raise exception 'Periksa fase, kondisi, dan warna pita sebelum panen'; end if;
   if p_event->>'color' is distinct from current_tree.color then raise exception 'Warna pita berubah; periksa lagi'; end if;
   event_date:=(p_event->>'date')::date;
   if event_date is null then raise exception 'Tanggal panen wajib diisi'; end if;
   wait_next:=current_tree.phase in ('R3','R4');
   state_next:=case current_tree.phase when 'PC' then 'R1' when 'R1' then 'R2' when 'R2' then 'R3' else current_tree.phase end;
   update public.ip_trees set phase=state_next,awaiting_decision=wait_next,color=null,version=version+1 where ip_trees.code=v_code returning * into current_tree;
  elsif typ='decision' then
   if not public.ip_member_allowed(true,true) or not current_tree.awaiting_decision then raise exception 'Keputusan fase hanya oleh admin'; end if;
   if p_event->>'action'='r4' and current_tree.phase<>'R3' then raise exception 'R4 hanya setelah R3'; end if;
   if p_event->>'action' not in ('r4','tanam_ulang') then raise exception 'Keputusan tidak valid'; end if;
   update public.ip_trees set phase=case when p_event->>'action'='r4' then 'R4' else 'PC' end,awaiting_decision=false,version=version+1 where ip_trees.code=v_code returning * into current_tree;
  end if;
 end if;
 result:=to_jsonb(current_tree);
 insert into public.ip_events(id,tree_code,actor,event_type,payload,result) values(ev_id,v_code,auth.uid(),typ,p_event,result);
 if typ='census' then insert into public.ip_census_entries(session_id,tree_code,event_id,expected_version,condition,note,color)
 values(sess,v_code,ev_id,current_tree.version,p_event->>'condition',left(trim(coalesce(p_event->>'note','')),500),nullif(p_event->>'color','')); end if;
 return result;
end $$;
revoke all on function public.ip_apply_event(jsonb) from public,anon;
grant execute on function public.ip_apply_event(jsonb) to authenticated;

create or replace function public.ip_get_tree(p_code text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare t public.ip_trees%rowtype; history jsonb;
begin
 if not public.ip_member_allowed(false,false) then raise exception 'Akun tidak memiliki akses'; end if;
 select * into t from public.ip_trees where code=p_code;
 if not found then return null; end if;
 select coalesce(jsonb_agg(jsonb_build_object('type',e.event_type,'payload',e.payload,'created_at',e.created_at,'petugas',m.display_name) order by e.created_at desc),'[]'::jsonb)
 into history from (select * from public.ip_events where tree_code=p_code order by created_at desc limit 100) e left join public.marking_members m on m.user_id=e.actor;
 return jsonb_build_object('tree',to_jsonb(t),'history',history);
end $$;
revoke all on function public.ip_get_tree(text) from public,anon;
grant execute on function public.ip_get_tree(text) to authenticated;

create or replace function public.ip_get_setup()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare batches jsonb; sessions jsonb; boundary jsonb;
begin
 if not public.ip_member_allowed(false,false) then raise exception 'Akun tidak memiliki akses'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'quantity',quantity,'created_at',created_at) order by created_at desc),'[]'::jsonb) into batches from public.ip_label_batches;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'block',block,'state',state,'created_at',created_at) order by created_at desc),'[]'::jsonb) into sessions from public.ip_census_sessions where state='open';
 select geojson into boundary from public.marking_boundaries where id='active';
 if boundary is null then raise exception 'Peta blok belum tersedia'; end if;
 return jsonb_build_object('batches',batches,'sessions',sessions,'boundary',boundary);
end $$;
revoke all on function public.ip_get_setup() from public,anon;
grant execute on function public.ip_get_setup() to authenticated;

create or replace function public.ip_get_map(p_block text,p_south float8,p_west float8,p_north float8,p_east float8)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare result jsonb;
begin
 if not public.ip_member_allowed(false,false) then raise exception 'Akun tidak memiliki akses'; end if;
 if length(trim(coalesce(p_block,'')))=0 or p_south not between -90 and 90 or p_north not between -90 and 90 or p_west not between -180 and 180 or p_east not between -180 and 180 or p_south>p_north or p_west>p_east then raise exception 'Pilih blok dan batas peta yang benar'; end if;
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into result from
 (select code,block,row_label,lat,lng,phase,condition,color,awaiting_decision,version from public.ip_trees
  where block=p_block and lat between p_south and p_north and lng between p_west and p_east order by code limit 2001) q;
 return result;
end $$;
revoke all on function public.ip_get_map(text,float8,float8,float8,float8) from public,anon;
grant execute on function public.ip_get_map(text,float8,float8,float8,float8) to authenticated;

create or replace function public.ip_session_summary(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare s public.ip_census_sessions%rowtype; c jsonb;
begin
 if not public.ip_member_allowed(false,false) then raise exception 'Akun tidak memiliki akses'; end if;
 select * into s from public.ip_census_sessions where id=p_id;
 if not found then raise exception 'Sesi tidak ditemukan'; end if;
 select jsonb_build_object('total',count(*),'hidup',count(*) filter(where condition='hidup'),'mati',count(*) filter(where condition='mati'),'lainnya',count(*) filter(where condition='lainnya')) into c from public.ip_census_entries where session_id=p_id;
 return jsonb_build_object('session',to_jsonb(s),'counts',c);
end $$;
revoke all on function public.ip_session_summary(uuid) from public,anon;
grant execute on function public.ip_session_summary(uuid) to authenticated;

create or replace function public.ip_list_sessions()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare result jsonb;
begin
 if not public.ip_member_allowed(false,false) then raise exception 'Akun tidak memiliki akses'; end if;
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into result from
 (select s.id,s.block,s.state,s.created_at,s.applied_at,count(e.tree_code) total,
 count(e.tree_code) filter(where e.condition='hidup') hidup,
 count(e.tree_code) filter(where e.condition='mati') mati,
 count(e.tree_code) filter(where e.condition='lainnya') lainnya
 from public.ip_census_sessions s left join public.ip_census_entries e on e.session_id=s.id
 group by s.id order by s.created_at desc limit 200) q;
 return result;
end $$;
revoke all on function public.ip_list_sessions() from public,anon;
grant execute on function public.ip_list_sessions() to authenticated;

create or replace function public.ip_session_export(p_id uuid,p_after text,p_limit integer default 1000)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare result jsonb;
begin
 if not exists(select 1 from public.marking_members m where m.user_id=auth.uid() and m.active=true and (m.role='admin' or m.report_access=true)) then raise exception 'Akun tidak memiliki hak unduh laporan'; end if;
 if p_limit not between 1 and 5000 then raise exception 'Ukuran halaman tidak valid'; end if;
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into result from
 (select e.tree_code,ev.result->>'block' block,ev.result->>'row_label' row_label,ev.result->>'phase' phase,
 e.condition,e.color,e.note,ev.payload->>'date' tanggal,m.display_name petugas
 from public.ip_census_entries e join public.ip_events ev on ev.id=e.event_id left join public.marking_members m on m.user_id=ev.actor
 where e.session_id=p_id and e.tree_code>coalesce(p_after,'') order by e.tree_code limit p_limit) q;
 return result;
end $$;
revoke all on function public.ip_session_export(uuid,text,integer) from public,anon;
grant execute on function public.ip_session_export(uuid,text,integer) to authenticated;
commit;
