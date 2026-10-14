-- =====================================================================
-- GUDANG TITATI - UPDATE: KIRIM KE CABANG (gudang kirim langsung, tanpa produksi)
-- Sebelumnya barang hanya sampai ke cabang bila cabang meminta. Sekarang kepala gudang
-- juga bisa membuat pengiriman sendiri: pilih cabang, pilih barang, langsung terkirim.
-- Barang yang boleh dikirim: bahan jadi, barang siap jual, dan barang jalur "langsung ke cabang"/"keduanya".
-- Tanpa ACC owner. Stok gudang langsung berkurang, cabang menekan Terima (selisih tampil merah di owner).
--
-- Jalankan PALING AKHIR, setelah supabase_master_data.sql. Aman diulang.
-- Jangan menjalankan ulang supabase_master_data.sql / supabase_update_acc_selektif.sql
-- sesudah file ini (fungsi create_doc akan tertimpa dan jenis dokumen baru tidak dikenal lagi).
-- =====================================================================

-- 1) Jenis dokumen baru
alter table public.docs drop constraint if exists docs_type_check;
alter table public.docs add constraint docs_type_check
  check (type in ('masuk','kirim_produksi','setor_jadi','minta_cabang','kirim_cabang'));

-- 2) Cabang boleh melihat pengiriman ke cabangnya sendiri
drop policy if exists p_docs_select on public.docs;
create policy p_docs_select on public.docs for select to authenticated
  using (public.me_role() in ('owner','gudang','produksi')
         or (public.me_role() = 'cabang' and type in ('minta_cabang','kirim_cabang') and branch = public.me_branch()));

-- 3) Daftar cabang untuk pilihan tujuan (gudang tidak boleh membaca tabel profil, jadi lewat fungsi ini)
create or replace function public.list_cabang() returns setof text
language sql stable security definer set search_path = public as $$
  select distinct branch from public.profiles where role = 'cabang' and coalesce(branch, '') <> '' order by 1
$$;

-- 4) Fungsi kirim, terima, dan buat dokumen yang mengenal jenis baru
create or replace function public.send_doc(p_doc uuid, p_lines jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.docs; v_role text := public.me_role(); r record; v_src text; have numeric;
  v_l jsonb; v_q numeric; v_old numeric; v_changed boolean := false; n_left int;
begin
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.type = 'masuk' then raise exception 'Barang masuk tidak perlu dikirim'; end if;
  if d.status <> 'disetujui' then raise exception 'Dokumen belum siap dikirim (status: %)', d.status; end if;
  if d.type in ('kirim_produksi','minta_cabang','kirim_cabang') then
    if v_role <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh mengirim'; end if;
    v_src := 'gudang';
  else
    if v_role <> 'produksi' then raise exception 'Hanya kepala produksi yang boleh mengirim setoran'; end if;
    v_src := 'produksi';
  end if;

  -- penyesuaian jumlah oleh gudang (khusus permintaan cabang, hanya boleh mengurangi)
  if p_lines is not null and jsonb_typeof(p_lines) = 'array' and jsonb_array_length(p_lines) > 0 then
    if d.type <> 'minta_cabang' then raise exception 'Jumlah dokumen ini tidak bisa diubah saat kirim'; end if;
    for v_l in select value from jsonb_array_elements(p_lines) loop
      v_q := (v_l->>'qty')::numeric;
      if v_q is null then continue; end if;
      select qty into v_old from public.doc_lines where id = (v_l->>'line_id')::uuid and doc_id = p_doc;
      if not found then continue; end if;
      if v_q > v_old then raise exception 'Gudang hanya boleh mengurangi jumlah (diminta %)', v_old; end if;
      if v_q <= 0 then
        delete from public.doc_lines where id = (v_l->>'line_id')::uuid and doc_id = p_doc;
        v_changed := true;
      elsif v_q <> v_old then
        update public.doc_lines set qty = v_q where id = (v_l->>'line_id')::uuid and doc_id = p_doc;
        v_changed := true;
      end if;
    end loop;
    select count(*) into n_left from public.doc_lines where doc_id = p_doc;
    if n_left = 0 then raise exception 'Semua barang dihapus. Jika tidak ada yang bisa dikirim, hubungi cabang atau owner.'; end if;
    if v_changed then perform public._log(p_doc, 'jumlah disesuaikan gudang', ''); end if;
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
  elsif d.type in ('minta_cabang','kirim_cabang') then
    if v_role <> 'cabang' or public.me_branch() <> d.branch then raise exception 'Hanya cabang tujuan yang boleh menerima'; end if;
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

create or replace function public.create_doc(p_type text, p_supplier text, p_note text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.me_role();
  v_branch text := '';
  v_id uuid; v_no text; v_prefix text; v_l jsonb; v_item public.items;
  v_lr text; v_qty numeric; v_price numeric; n_pakai int := 0; n_hasil int := 0; r record;
  v_alasan text := '';
begin
  if auth.uid() is null then raise exception 'Belum login'; end if;
  if p_type in ('masuk','kirim_produksi') then
    if v_role <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh membuat dokumen ini'; end if;
  elsif p_type = 'setor_jadi' then
    if v_role <> 'produksi' then raise exception 'Hanya kepala produksi yang boleh membuat setoran'; end if;
  elsif p_type = 'kirim_cabang' then
    if v_role <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh mengirim ke cabang'; end if;
    v_branch := trim(coalesce(p_supplier, ''));   -- untuk jenis ini p_supplier berisi nama cabang tujuan
    if v_branch = '' or not exists (select 1 from public.profiles where role = 'cabang' and branch = v_branch) then
      raise exception 'Pilih cabang tujuan yang valid';
    end if;
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

  v_prefix := case p_type when 'masuk' then 'BM' when 'kirim_produksi' then 'KP' when 'setor_jadi' then 'SJ' when 'kirim_cabang' then 'KC' else 'PC' end;
  v_no := v_prefix || to_char(now() at time zone 'Asia/Jakarta', 'YYMMDD') || '-' || lpad((nextval('public.doc_seq') % 10000)::text, 4, '0');

  insert into public.docs (no, type, branch, supplier, note, created_by_name)
  values (v_no, p_type, v_branch, case when p_type = 'kirim_cabang' then '' else coalesce(p_supplier, '') end, coalesce(p_note, ''), public.me_name())
  returning id into v_id;

  for v_l in select value from jsonb_array_elements(p_lines) loop
    v_qty := (v_l->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Jumlah harus lebih dari 0'; end if;
    select * into v_item from public.items where id = (v_l->>'item_id')::uuid and active;
    if not found then raise exception 'Bahan tidak ditemukan atau sudah nonaktif'; end if;
    v_lr := coalesce(nullif(v_l->>'role', ''), 'item');
    v_price := coalesce(nullif(v_l->>'unit_price', '')::numeric, 0);
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
      if p_type = 'kirim_produksi' and (v_item.siap_jual or not v_item.untuk_produksi) then raise exception '% tidak diolah di produksi (kirim langsung ke cabang)', v_item.name; end if;
      if p_type in ('minta_cabang','kirim_cabang') and v_item.kind <> 'jadi' and not v_item.siap_jual and not v_item.ke_cabang then raise exception '% tidak bisa diminta cabang', v_item.name; end if;
      if p_type = 'masuk' and v_price <= 0 then raise exception 'Harga satuan % wajib diisi', v_item.name; end if;
    end if;
    insert into public.doc_lines (doc_id, item_id, role, qty, unit_price)
    values (v_id, v_item.id, v_lr, v_qty, v_price);
  end loop;

  if p_type = 'setor_jadi' and (n_pakai = 0 or n_hasil = 0) then
    raise exception 'Setoran harus berisi bahan yang dipakai DAN hasil jadi';
  end if;
  perform public._log(v_id, 'dibuat', '');

  if p_type = 'masuk' then
    -- stok langsung bertambah; owner memverifikasi harga/pembelian menyusul
    for r in select item_id, qty from public.doc_lines where doc_id = v_id loop
      insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values ('gudang', r.item_id, r.qty, v_id, public.me_name());
    end loop;
    update public.doc_lines set qty_received = qty where doc_id = v_id;
    update public.docs set status = 'diterima', received_at = now(), received_by_name = public.me_name(), verif = 'menunggu' where id = v_id;
    perform public._log(v_id, 'stok gudang bertambah', 'belum diverifikasi owner');
  elsif p_type = 'kirim_produksi' then
    update public.docs set status = 'disetujui' where id = v_id;
    perform public.send_doc(v_id);
  elsif p_type = 'setor_jadi' then
    v_alasan := public._setor_alasan(v_id);
    if v_alasan = '' then
      update public.docs set status = 'disetujui' where id = v_id;
      perform public.send_doc(v_id);
    else
      update public.docs set status = 'diajukan', acc_reason = v_alasan where id = v_id;
      perform public._log(v_id, 'menunggu ACC owner (menyimpang)', v_alasan);
    end if;
  elsif p_type = 'kirim_cabang' then
    -- gudang kirim langsung ke cabang: tanpa ACC, stok gudang langsung berkurang, cabang menekan Terima
    update public.docs set status = 'disetujui' where id = v_id;
    perform public.send_doc(v_id);
  else
    v_alasan := public._minta_alasan(v_id, v_branch);
    if v_alasan = '' then
      update public.docs set status = 'disetujui' where id = v_id;   -- antre di gudang
    else
      update public.docs set status = 'diajukan', acc_reason = v_alasan where id = v_id;
      perform public._log(v_id, 'menunggu ACC owner (jumlah jauh di atas biasanya)', v_alasan);
    end if;
  end if;
  return v_id;
end $$;

-- 5) Izin
revoke execute on function public.list_cabang() from public, anon;
revoke execute on function public.send_doc(uuid, jsonb) from public, anon;
revoke execute on function public.receive_doc(uuid, jsonb) from public, anon;
revoke execute on function public.create_doc(text, text, text, jsonb) from public, anon;
grant execute on function public.list_cabang() to authenticated;
grant execute on function public.send_doc(uuid, jsonb) to authenticated;
grant execute on function public.receive_doc(uuid, jsonb) to authenticated;
grant execute on function public.create_doc(text, text, text, jsonb) to authenticated;

notify pgrst, 'reload schema';
