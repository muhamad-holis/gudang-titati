-- =====================================================================
-- GUDANG TITATI - UPDATE: SATUAN GANDA (GUDANG DUS, CABANG ECER BOTOL)
--
-- Contoh minuman: gudang membeli dan mengirim per DUS, cabang menjual per BOTOL.
--  * Satu nama barang saja (mis. "Air Mineral 600 ml"), satuan barang = "dus".
--  * Kolom baru items.unit_ecer (mis. "botol") dan items.isi_ecer (isi per dus, mis. 24).
--  * Gudang dan semua dokumen (Barang Masuk, Kirim ke Cabang, Permintaan Cabang, bon, omzet,
--    tagihan) tetap dicatat dalam DUS. Harga beli dan harga jual per dus.
--  * Stok CABANG dicatat dalam BOTOL: saat cabang menekan Terima, stok cabang bertambah
--    jumlah diterima x isi per dus (2 dus = 48 botol). Penjualan cabang dicatat per botol.
--  * Rekap cabang (Masuk, Terjual, Sisa) dan stok cabang tampil dalam satuan eceran.
--  * Barang tanpa satuan eceran berjalan seperti biasa (tidak ada yang berubah).
--
-- Mengatur satuan eceran: lewat aplikasi (Ubah barang) atau fungsi atur_satuan_ecer di bawah.
-- Bila barang sudah punya stok di cabang (masih dalam dus) saat satuan eceran pertama kali
-- diatur, stok cabang itu otomatis dikonversi ke botol (dicatat sebagai koreksi stok).
--
-- JALANKAN SETELAH supabase_update_kirim_cabang.sql dan supabase_update_stok_kosong.sql
-- (urutan bebas terhadap file omzet_tagihan / harga_standar). Aman diulang.
-- JANGAN menjalankan ulang supabase_update_kirim_cabang.sql sesudah file ini, karena
-- receive_doc akan kembali ke versi lama (stok cabang tidak dikonversi ke botol).
-- =====================================================================

alter table public.items add column if not exists unit_ecer text not null default '';
alter table public.items add column if not exists isi_ecer numeric not null default 1;
alter table public.items drop constraint if exists items_isi_ecer_check;
alter table public.items add constraint items_isi_ecer_check check (isi_ecer >= 1);

-- Tampilan stok dan rekap: lokasi cabang memakai satuan eceran bila barangnya punya.
create or replace view public.v_stock with (security_invoker = true) as
  select l.location, l.item_id, i.name, i.category,
         case when l.location not in ('gudang', 'produksi') and i.unit_ecer <> '' and i.isi_ecer > 1 then i.unit_ecer else i.unit end as unit,
         i.kind, sum(l.delta) as qty
  from public.stock_ledger l join public.items i on i.id = l.item_id
  group by 1, 2, 3, 4, 5, 6
  having sum(l.delta) <> 0;

create or replace view public.v_rekap_harian with (security_invoker = true) as
  select (l.at at time zone 'Asia/Jakarta')::date as hari,
         l.location, l.item_id, i.name, i.category,
         case when i.unit_ecer <> '' and i.isi_ecer > 1 then i.unit_ecer else i.unit end as unit,
         coalesce(sum(l.delta) filter (where l.kind = 'doc' and l.delta > 0), 0) as masuk,
         coalesce(-sum(l.delta) filter (where l.kind in ('jual', 'jual_batal')), 0) as terjual
  from public.stock_ledger l join public.items i on i.id = l.item_id
  where l.location not in ('gudang', 'produksi')
  group by 1, 2, 3, 4, 5, 6
  having coalesce(sum(l.delta) filter (where l.kind = 'doc' and l.delta > 0), 0) <> 0
      or coalesce(-sum(l.delta) filter (where l.kind in ('jual', 'jual_batal')), 0) <> 0;

grant select on public.v_stock, public.v_rekap_harian to authenticated;

-- Terima barang: stok cabang bertambah dalam satuan eceran (jumlah diterima x isi per dus).
-- Selain itu sama persis dengan versi di supabase_update_kirim_cabang.sql.
create or replace function public.receive_doc(p_doc uuid, p_lines jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare d public.docs; v_role text := public.me_role(); v_dest text; r record; v_recv numeric; v_diff boolean := false; v_mult numeric;
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

  for r in select l.id, l.item_id, l.qty, l.role, i.name, i.unit_ecer, i.isi_ecer
             from public.doc_lines l join public.items i on i.id = l.item_id where l.doc_id = p_doc loop
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
      v_mult := case when d.type in ('minta_cabang','kirim_cabang') and r.unit_ecer <> '' and r.isi_ecer > 1 then r.isi_ecer else 1 end;
      insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values (v_dest, r.item_id, v_recv * v_mult, p_doc, public.me_name());
    end if;
  end loop;
  update public.docs set status = 'diterima', received_at = now(), received_by_name = public.me_name() where id = p_doc;
  perform public._log(p_doc, case when v_diff then 'diterima (ada selisih)' else 'diterima' end, '');
end $$;

-- Atur satuan eceran sebuah barang. p_unit kosong = tanpa satuan eceran.
-- Pertama kali diatur: stok cabang yang sudah ada (dalam satuan barang) dikonversi ke satuan eceran.
create or replace function public.atur_satuan_ecer(p_item uuid, p_unit text, p_isi numeric) returns void
language plpgsql security definer set search_path = public as $$
declare it public.items; v_unit text := trim(coalesce(p_unit, '')); v_isi numeric := coalesce(p_isi, 1);
        v_old boolean; v_new boolean; c record;
begin
  if public.me_role() not in ('owner', 'gudang') then raise exception 'Hanya owner atau kepala gudang yang boleh mengatur satuan eceran'; end if;
  select * into it from public.items where id = p_item for update;
  if not found then raise exception 'Barang tidak ditemukan'; end if;
  if v_unit = '' then v_isi := 1; end if;
  if v_unit <> '' and v_isi <= 1 then raise exception 'Isi per % harus lebih dari 1', it.unit; end if;
  if v_isi <> trunc(v_isi) then raise exception 'Isi per % harus bilangan bulat', it.unit; end if;
  v_old := it.unit_ecer <> '' and it.isi_ecer > 1;
  v_new := v_unit <> '' and v_isi > 1;

  if not v_old and v_new then
    for c in select location, sum(delta) as qty from public.stock_ledger
              where item_id = p_item and location not in ('gudang', 'produksi')
              group by location having sum(delta) <> 0 loop
      insert into public.stock_ledger (location, item_id, delta, kind, reason, by_name)
      values (c.location, p_item, c.qty * (v_isi - 1), 'koreksi',
              'Konversi satuan ' || it.unit || ' ke ' || v_unit || ' (isi ' || v_isi::text || ')', public.me_name());
    end loop;
  elsif v_old and not v_new then
    if exists (select 1 from public.stock_ledger where item_id = p_item and location not in ('gudang', 'produksi') group by location having sum(delta) <> 0) then
      raise exception 'Satuan eceran tidak bisa dihapus selama masih ada stok di cabang';
    end if;
  end if;

  update public.items set unit_ecer = v_unit, isi_ecer = v_isi where id = p_item;
end $$;

revoke execute on function public.receive_doc(uuid, jsonb) from public, anon;
revoke execute on function public.atur_satuan_ecer(uuid, text, numeric) from public, anon;
grant execute on function public.receive_doc(uuid, jsonb) to authenticated;
grant execute on function public.atur_satuan_ecer(uuid, text, numeric) to authenticated;

notify pgrst, 'reload schema';
