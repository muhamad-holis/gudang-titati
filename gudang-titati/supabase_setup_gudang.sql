-- =====================================================================
-- GUDANG TITATI - SETUP DATABASE (project Supabase BARU, terpisah dari kasir)
-- Supabase -> SQL Editor -> New query -> paste SEMUA -> Run. Aman diulang.
-- =====================================================================

-- ---------- TABEL ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  role text not null default 'cabang' check (role in ('owner','gudang','produksi','cabang')),
  branch text not null default ''
);

create table if not exists public.categories (name text primary key);

create table if not exists public.items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind text not null check (kind in ('mentah','jadi')),
  category text not null default 'Lainnya',
  unit text not null default 'pcs',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (kind, name)
);

create sequence if not exists public.doc_seq;

create table if not exists public.docs (
  id uuid primary key default gen_random_uuid(),
  no text not null,
  type text not null check (type in ('masuk','kirim_produksi','setor_jadi','minta_cabang')),
  status text not null default 'diajukan' check (status in ('diajukan','disetujui','dikirim','diterima','ditolak','dibatalkan')),
  branch text not null default '',
  supplier text not null default '',
  note text not null default '',
  owner_note text not null default '',
  created_by uuid default auth.uid(),
  created_by_name text not null default '',
  created_at timestamptz not null default now(),
  approved_by_name text not null default '',
  approved_at timestamptz,
  sent_at timestamptz,
  received_by_name text not null default '',
  received_at timestamptz
);

create table if not exists public.doc_lines (
  id uuid primary key default gen_random_uuid(),
  doc_id uuid not null references public.docs(id) on delete cascade,
  item_id uuid not null references public.items(id),
  role text not null default 'item' check (role in ('item','pakai','hasil')),
  qty numeric not null check (qty > 0),
  qty_received numeric,
  unit_price numeric not null default 0 check (unit_price >= 0)
);

create table if not exists public.doc_log (
  id bigint generated always as identity primary key,
  doc_id uuid not null references public.docs(id) on delete cascade,
  at timestamptz not null default now(),
  by_name text not null default '',
  by_role text not null default '',
  action text not null,
  detail text not null default ''
);

create table if not exists public.stock_ledger (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  location text not null,
  item_id uuid not null references public.items(id),
  delta numeric not null,
  doc_id uuid references public.docs(id) on delete set null,
  kind text not null default 'doc' check (kind in ('doc','koreksi')),
  reason text not null default '',
  by_name text not null default ''
);

create index if not exists docs_created_idx on public.docs (created_at desc);
create index if not exists doc_lines_doc_idx on public.doc_lines (doc_id);
create index if not exists doc_log_doc_idx on public.doc_log (doc_id);
create index if not exists ledger_loc_idx on public.stock_ledger (location, item_id);

-- stok = jumlah semua pergerakan (tidak bisa "melenceng")
create or replace view public.v_stock with (security_invoker = true) as
  select l.location, l.item_id, i.name, i.category, i.unit, i.kind, sum(l.delta) as qty
  from public.stock_ledger l join public.items i on i.id = l.item_id
  group by l.location, l.item_id, i.name, i.category, i.unit, i.kind
  having sum(l.delta) <> 0;

insert into public.categories (name) values
  ('Daging'), ('Mie ayam'), ('Bumbu'), ('Sayur'), ('Buah'), ('Minuman'), ('Lainnya')
on conflict do nothing;

-- ---------- FUNGSI BANTU ----------
create or replace function public.me_role() returns text
language sql stable security definer set search_path = public as
$$ select coalesce((select role from public.profiles where id = auth.uid()), '') $$;

create or replace function public.me_branch() returns text
language sql stable security definer set search_path = public as
$$ select coalesce((select branch from public.profiles where id = auth.uid()), '') $$;

create or replace function public.me_name() returns text
language sql stable security definer set search_path = public as
$$ select coalesce((select name from public.profiles where id = auth.uid()), '') $$;

create or replace function public._log(p_doc uuid, p_action text, p_detail text default '') returns void
language sql as
$$ insert into public.doc_log (doc_id, by_name, by_role, action, detail)
   values (p_doc, public.me_name(), public.me_role(), p_action, p_detail) $$;

-- ---------- AKSI (semua perubahan data lewat fungsi ini) ----------

-- Buat dokumen. p_lines: [{"item_id":"...","qty":5,"role":"item|pakai|hasil","unit_price":0}]
create or replace function public.create_doc(p_type text, p_supplier text, p_note text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.me_role();
  v_branch text := '';
  v_id uuid; v_no text; v_prefix text; v_l jsonb; v_item public.items;
  v_lr text; v_qty numeric; n_pakai int := 0; n_hasil int := 0;
begin
  if auth.uid() is null then raise exception 'Belum login'; end if;
  if p_type in ('masuk','kirim_produksi') then
    if v_role <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh membuat dokumen ini'; end if;
  elsif p_type = 'setor_jadi' then
    if v_role <> 'produksi' then raise exception 'Hanya kepala produksi yang boleh membuat setoran'; end if;
  elsif p_type = 'minta_cabang' then
    if v_role <> 'cabang' then raise exception 'Hanya akun cabang yang boleh membuat permintaan'; end if;
    v_branch := public.me_branch();
    if v_branch = '' then raise exception 'Akun cabang ini belum diberi nama cabang'; end if;
  else
    raise exception 'Jenis dokumen tidak dikenal';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Isi minimal satu barang';
  end if;

  v_prefix := case p_type when 'masuk' then 'BM' when 'kirim_produksi' then 'KP' when 'setor_jadi' then 'SJ' else 'PC' end;
  v_no := v_prefix || to_char(now() at time zone 'Asia/Jakarta', 'YYMMDD') || '-' || lpad((nextval('public.doc_seq') % 10000)::text, 4, '0');

  insert into public.docs (no, type, branch, supplier, note, created_by_name)
  values (v_no, p_type, v_branch, coalesce(p_supplier, ''), coalesce(p_note, ''), public.me_name())
  returning id into v_id;

  for v_l in select value from jsonb_array_elements(p_lines) loop
    v_qty := (v_l->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Jumlah harus lebih dari 0'; end if;
    select * into v_item from public.items where id = (v_l->>'item_id')::uuid and active;
    if not found then raise exception 'Bahan tidak ditemukan atau sudah nonaktif'; end if;
    v_lr := coalesce(nullif(v_l->>'role', ''), 'item');
    if p_type = 'setor_jadi' then
      if v_lr = 'pakai' then
        if v_item.kind <> 'mentah' then raise exception '% bukan bahan mentah', v_item.name; end if;
        n_pakai := n_pakai + 1;
      elsif v_lr = 'hasil' then
        if v_item.kind <> 'jadi' then raise exception '% bukan bahan jadi', v_item.name; end if;
        n_hasil := n_hasil + 1;
      else
        raise exception 'Baris setoran tidak valid';
      end if;
    else
      v_lr := 'item';
      if p_type in ('masuk','kirim_produksi') and v_item.kind <> 'mentah' then raise exception '% bukan bahan mentah', v_item.name; end if;
      if p_type = 'minta_cabang' and v_item.kind <> 'jadi' then raise exception '% bukan bahan jadi', v_item.name; end if;
    end if;
    insert into public.doc_lines (doc_id, item_id, role, qty, unit_price)
    values (v_id, v_item.id, v_lr, v_qty, coalesce(nullif(v_l->>'unit_price', '')::numeric, 0));
  end loop;

  if p_type = 'setor_jadi' and (n_pakai = 0 or n_hasil = 0) then
    raise exception 'Setoran harus berisi bahan yang dipakai DAN hasil jadi';
  end if;
  perform public._log(v_id, 'dibuat', '');
  return v_id;
end $$;

-- Ubah jumlah baris (khusus owner, sebelum dikirim). [{"line_id":"...","qty":3}] qty 0 = hapus baris
create or replace function public._apply_edits(p_doc uuid, p_lines jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_l jsonb; v_q numeric; v_changed boolean := false; v_type text; v_status text; n_left int; n_pakai int; n_hasil int;
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang boleh mengubah'; end if;
  select type, status into v_type, v_status from public.docs where id = p_doc;
  if v_status not in ('diajukan','disetujui') then raise exception 'Dokumen sudah dikirim, tidak bisa diubah. Gunakan koreksi stok.'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then return false; end if;
  for v_l in select value from jsonb_array_elements(p_lines) loop
    v_q := (v_l->>'qty')::numeric;
    if v_q is null then continue; end if;
    if v_q <= 0 then
      delete from public.doc_lines where id = (v_l->>'line_id')::uuid and doc_id = p_doc;
    else
      update public.doc_lines set qty = v_q where id = (v_l->>'line_id')::uuid and doc_id = p_doc and qty <> v_q;
    end if;
    if found then v_changed := true; end if;
  end loop;
  select count(*) into n_left from public.doc_lines where doc_id = p_doc;
  if n_left = 0 then raise exception 'Dokumen tidak boleh kosong. Gunakan Tolak jika ingin membatalkan.'; end if;
  if v_type = 'setor_jadi' then
    select count(*) filter (where role = 'pakai'), count(*) filter (where role = 'hasil') into n_pakai, n_hasil
      from public.doc_lines where doc_id = p_doc;
    if n_pakai = 0 or n_hasil = 0 then raise exception 'Setoran harus tetap punya bahan dipakai dan hasil jadi'; end if;
  end if;
  return v_changed;
end $$;

-- Owner memutuskan: p_action 'acc' atau 'tolak' (alasan wajib untuk tolak)
create or replace function public.owner_decide(p_doc uuid, p_action text, p_note text default '', p_lines jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare d public.docs; v_changed boolean := false; r record; v_note text := coalesce(trim(p_note), '');
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang boleh memutuskan'; end if;
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.status <> 'diajukan' then raise exception 'Dokumen sudah diproses (status: %)', d.status; end if;

  if p_action = 'tolak' then
    if v_note = '' then raise exception 'Alasan penolakan wajib diisi'; end if;
    update public.docs set status = 'ditolak', owner_note = v_note, approved_by_name = public.me_name(), approved_at = now() where id = p_doc;
    perform public._log(p_doc, 'ditolak', v_note);
  elsif p_action = 'acc' then
    v_changed := public._apply_edits(p_doc, p_lines);
    update public.docs set status = 'disetujui', owner_note = v_note, approved_by_name = public.me_name(), approved_at = now() where id = p_doc;
    perform public._log(p_doc, case when v_changed then 'disetujui (jumlah diubah owner)' else 'disetujui' end, v_note);
    if d.type = 'masuk' then
      -- barang masuk: setelah ACC langsung menambah stok gudang
      for r in select item_id, qty from public.doc_lines where doc_id = p_doc loop
        insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values ('gudang', r.item_id, r.qty, p_doc, public.me_name());
      end loop;
      update public.doc_lines set qty_received = qty where doc_id = p_doc;
      update public.docs set status = 'diterima', received_at = now(), received_by_name = d.created_by_name where id = p_doc;
      perform public._log(p_doc, 'stok gudang bertambah', '');
    end if;
  else
    raise exception 'Aksi tidak dikenal';
  end if;
end $$;

-- Owner mengubah jumlah pada dokumen yang sudah disetujui tapi belum dikirim
create or replace function public.owner_edit(p_doc uuid, p_lines jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare d public.docs; v_changed boolean;
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang boleh mengubah'; end if;
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.status <> 'disetujui' then raise exception 'Hanya dokumen berstatus disetujui yang bisa diubah di sini'; end if;
  v_changed := public._apply_edits(p_doc, p_lines);
  if v_changed then perform public._log(p_doc, 'jumlah diubah owner', ''); end if;
end $$;

-- Pengirim mengirim barang: stok sumber berkurang (barang "dalam perjalanan")
create or replace function public.send_doc(p_doc uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.docs; v_role text := public.me_role(); r record; v_src text; have numeric;
begin
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.type = 'masuk' then raise exception 'Barang masuk tidak perlu dikirim'; end if;
  if d.status <> 'disetujui' then raise exception 'Dokumen belum disetujui owner (status: %)', d.status; end if;
  if d.type in ('kirim_produksi','minta_cabang') then
    if v_role <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh mengirim'; end if;
    v_src := 'gudang';
  else
    if v_role <> 'produksi' then raise exception 'Hanya kepala produksi yang boleh mengirim setoran'; end if;
    v_src := 'produksi';
  end if;

  for r in select l.item_id, l.qty, l.role, i.name from public.doc_lines l join public.items i on i.id = l.item_id where l.doc_id = p_doc loop
    if d.type = 'setor_jadi' and r.role <> 'pakai' then continue; end if;
    select coalesce(sum(delta), 0) into have from public.stock_ledger where location = v_src and item_id = r.item_id;
    if have < r.qty then raise exception 'Stok % tidak cukup: tersedia %, dibutuhkan %', r.name, have, r.qty; end if;
  end loop;
  for r in select l.item_id, l.qty, l.role from public.doc_lines l where l.doc_id = p_doc loop
    if d.type = 'setor_jadi' and r.role <> 'pakai' then continue; end if;
    insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values (v_src, r.item_id, -r.qty, p_doc, public.me_name());
  end loop;
  update public.docs set status = 'dikirim', sent_at = now() where id = p_doc;
  perform public._log(p_doc, 'dikirim', '');
end $$;

-- Penerima konfirmasi terima. [{"line_id":"...","qty_received":4}] (baris yang tidak disebut = diterima penuh)
create or replace function public.receive_doc(p_doc uuid, p_lines jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare d public.docs; v_role text := public.me_role(); v_dest text; r record; v_recv numeric; v_diff boolean := false;
begin
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.status <> 'dikirim' then raise exception 'Dokumen belum dikirim atau sudah diterima (status: %)', d.status; end if;
  if d.type = 'kirim_produksi' then
    if v_role <> 'produksi' then raise exception 'Hanya kepala produksi yang boleh menerima bahan mentah'; end if;
    v_dest := 'produksi';
  elsif d.type = 'setor_jadi' then
    if v_role <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh menerima bahan jadi'; end if;
    v_dest := 'gudang';
  elsif d.type = 'minta_cabang' then
    if v_role <> 'cabang' or public.me_branch() <> d.branch then raise exception 'Hanya cabang peminta yang boleh menerima'; end if;
    v_dest := d.branch;
  else
    raise exception 'Jenis dokumen ini tidak diterima lewat sini';
  end if;

  for r in select l.id, l.item_id, l.qty, l.role, i.name from public.doc_lines l join public.items i on i.id = l.item_id where l.doc_id = p_doc loop
    if d.type = 'setor_jadi' and r.role <> 'hasil' then
      update public.doc_lines set qty_received = r.qty where id = r.id;
      continue;
    end if;
    v_recv := null;
    if p_lines is not null and jsonb_typeof(p_lines) = 'array' then
      select (t.e->>'qty_received')::numeric into v_recv from jsonb_array_elements(p_lines) as t(e) where t.e->>'line_id' = r.id::text limit 1;
    end if;
    v_recv := coalesce(v_recv, r.qty);
    if v_recv < 0 or v_recv > r.qty then raise exception 'Jumlah diterima untuk % harus antara 0 dan %', r.name, r.qty; end if;
    update public.doc_lines set qty_received = v_recv where id = r.id;
    if v_recv <> r.qty then v_diff := true; end if;
    if v_recv > 0 then
      insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values (v_dest, r.item_id, v_recv, p_doc, public.me_name());
    end if;
  end loop;
  update public.docs set status = 'diterima', received_at = now(), received_by_name = public.me_name() where id = p_doc;
  perform public._log(p_doc, case when v_diff then 'diterima (ada selisih)' else 'diterima' end, '');
end $$;

-- Pembuat membatalkan dokumennya sendiri selama belum diputuskan owner
create or replace function public.cancel_doc(p_doc uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.docs;
begin
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.created_by is distinct from auth.uid() then raise exception 'Hanya pembuat dokumen yang boleh membatalkan'; end if;
  if d.status <> 'diajukan' then raise exception 'Hanya dokumen yang menunggu ACC yang bisa dibatalkan'; end if;
  update public.docs set status = 'dibatalkan' where id = p_doc;
  perform public._log(p_doc, 'dibatalkan', '');
end $$;

-- Owner mengoreksi stok (hasil hitung fisik). Tercatat dengan alasan.
create or replace function public.koreksi_stok(p_location text, p_item uuid, p_new_qty numeric, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare have numeric; v_reason text := coalesce(trim(p_reason), '');
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang boleh mengoreksi stok'; end if;
  if p_new_qty is null or p_new_qty < 0 then raise exception 'Jumlah tidak valid'; end if;
  if v_reason = '' then raise exception 'Alasan koreksi wajib diisi'; end if;
  if p_location not in ('gudang','produksi') and not exists (select 1 from public.profiles where role = 'cabang' and branch = p_location) then
    raise exception 'Lokasi tidak dikenal';
  end if;
  select coalesce(sum(delta), 0) into have from public.stock_ledger where location = p_location and item_id = p_item;
  if p_new_qty = have then return; end if;
  insert into public.stock_ledger (location, item_id, delta, kind, reason, by_name)
  values (p_location, p_item, p_new_qty - have, 'koreksi', v_reason, public.me_name());
end $$;

-- ---------- PROFIL OTOMATIS SAAT AKUN DIBUAT ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- ---------- KEAMANAN (RLS) ----------
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.items enable row level security;
alter table public.docs enable row level security;
alter table public.doc_lines enable row level security;
alter table public.doc_log enable row level security;
alter table public.stock_ledger enable row level security;

drop policy if exists p_profiles_select on public.profiles;
create policy p_profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.me_role() = 'owner');

drop policy if exists p_cat_select on public.categories;
create policy p_cat_select on public.categories for select to authenticated using (true);
drop policy if exists p_cat_insert on public.categories;
create policy p_cat_insert on public.categories for insert to authenticated with check (public.me_role() in ('owner','gudang','produksi'));
drop policy if exists p_cat_delete on public.categories;
create policy p_cat_delete on public.categories for delete to authenticated using (public.me_role() = 'owner');

drop policy if exists p_items_select on public.items;
create policy p_items_select on public.items for select to authenticated using (true);
drop policy if exists p_items_insert on public.items;
create policy p_items_insert on public.items for insert to authenticated with check (public.me_role() in ('owner','gudang','produksi'));
drop policy if exists p_items_update on public.items;
create policy p_items_update on public.items for update to authenticated using (public.me_role() = 'owner') with check (public.me_role() = 'owner');
drop policy if exists p_items_delete on public.items;
create policy p_items_delete on public.items for delete to authenticated using (public.me_role() = 'owner');

drop policy if exists p_docs_select on public.docs;
create policy p_docs_select on public.docs for select to authenticated
  using (public.me_role() in ('owner','gudang','produksi')
         or (public.me_role() = 'cabang' and type = 'minta_cabang' and branch = public.me_branch()));

drop policy if exists p_lines_select on public.doc_lines;
create policy p_lines_select on public.doc_lines for select to authenticated
  using (exists (select 1 from public.docs d where d.id = doc_lines.doc_id));

drop policy if exists p_log_select on public.doc_log;
create policy p_log_select on public.doc_log for select to authenticated
  using (exists (select 1 from public.docs d where d.id = doc_log.doc_id));

drop policy if exists p_ledger_select on public.stock_ledger;
create policy p_ledger_select on public.stock_ledger for select to authenticated
  using (public.me_role() in ('owner','gudang','produksi')
         or (public.me_role() = 'cabang' and location = public.me_branch()));

-- ---------- IZIN ----------
grant usage on schema public to authenticated;
grant select on public.profiles, public.categories, public.items, public.docs, public.doc_lines,
               public.doc_log, public.stock_ledger, public.v_stock to authenticated;
grant insert on public.categories, public.items to authenticated;
grant update, delete on public.items to authenticated;
grant delete on public.categories to authenticated;

revoke execute on function public.create_doc(text, text, text, jsonb) from public, anon;
revoke execute on function public.owner_decide(uuid, text, text, jsonb) from public, anon;
revoke execute on function public.owner_edit(uuid, jsonb) from public, anon;
revoke execute on function public.send_doc(uuid) from public, anon;
revoke execute on function public.receive_doc(uuid, jsonb) from public, anon;
revoke execute on function public.cancel_doc(uuid) from public, anon;
revoke execute on function public.koreksi_stok(text, uuid, numeric, text) from public, anon;
revoke execute on function public._apply_edits(uuid, jsonb) from public, anon;
grant execute on function public.create_doc(text, text, text, jsonb) to authenticated;
grant execute on function public.owner_decide(uuid, text, text, jsonb) to authenticated;
grant execute on function public.owner_edit(uuid, jsonb) to authenticated;
grant execute on function public.send_doc(uuid) to authenticated;
grant execute on function public.receive_doc(uuid, jsonb) to authenticated;
grant execute on function public.cancel_doc(uuid) to authenticated;
grant execute on function public.koreksi_stok(text, uuid, numeric, text) to authenticated;
grant execute on function public._apply_edits(uuid, jsonb) to authenticated;
grant execute on function public.me_role() to authenticated;
grant execute on function public.me_branch() to authenticated;
grant execute on function public.me_name() to authenticated;

notify pgrst, 'reload schema';
