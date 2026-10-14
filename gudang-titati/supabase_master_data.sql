-- =====================================================================
-- GUDANG TITATI - UPDATE: MASTER DATA BAHAN + JALUR BARANG
-- Sumber: Master_Data_Bahan_Baku_Bakso_Mie_Ayam.pdf (71 baris, setelah nama kembar
-- digabung menjadi 51 barang unik, karena stok dicatat per nama barang).
--
-- JALUR BARANG (semua berjenis "mentah" agar bisa dibeli lewat Barang Masuk):
--   olah   (6) : hanya dikirim gudang ke PRODUKSI untuk diolah jadi bakso.
--   dua    (9) : dipakai produksi DAN dibutuhkan cabang (bumbu, daging ayam, tetelan, terigu).
--   cabang (36) : langsung gudang -> cabang, TANPA produksi, tidak dijual satuan
--                     (mie, telur, sayuran, saus meja, kemasan, dll).
-- Barang jadi hasil produksi (bakso, dll) tidak ada di PDF, tambahkan lewat Master > Bahan jadi.
--
-- Jalankan SETELAH: supabase_setup_gudang.sql, supabase_update_penjualan.sql,
-- supabase_update_siap_jual.sql, supabase_update_alur_tanpa_acc.sql,
-- supabase_update_acc_selektif.sql. Aman diulang. Jangan menjalankan ulang
-- supabase_update_acc_selektif.sql setelah file ini (fungsi create_doc akan tertimpa).
-- =====================================================================

-- 1) KOLOM JALUR
alter table public.items add column if not exists untuk_produksi boolean not null default true;
alter table public.items add column if not exists ke_cabang boolean not null default false;

-- 2) ATURAN DOKUMEN
--    Kirim ke produksi: hanya bahan yang diolah. Permintaan cabang: bahan jadi, barang siap jual,
--    atau barang jalur cabang/dua. Penjualan tetap hanya untuk bahan jadi dan barang siap jual.
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
      if p_type = 'minta_cabang' and v_item.kind <> 'jadi' and not v_item.siap_jual and not v_item.ke_cabang then raise exception '% tidak bisa diminta cabang', v_item.name; end if;
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

revoke execute on function public.create_doc(text, text, text, jsonb) from public, anon;
grant execute on function public.create_doc(text, text, text, jsonb) to authenticated;

-- 3) KATEGORI
insert into public.categories (name) values ('Daging'), ('Tulang'), ('Tepung'), ('Bahan produksi'), ('Bumbu'), ('Mie'), ('Telur'), ('Minyak'), ('Sayuran'), ('Pelengkap'), ('Saus & bumbu meja'), ('Kemasan')
on conflict do nothing;

-- 4) DATA BARANG (nama yang sudah ada, huruf besar/kecil diabaikan, tidak dibuat ganda)
drop table if exists pg_temp._master_barang;
create temp table _master_barang (name text, unit text, category text, untuk_produksi boolean, ke_cabang boolean);
insert into _master_barang (name, unit, category, untuk_produksi, ke_cabang) values
  ('Daging sapi', 'kg', 'Daging', true, false),
  ('Daging ayam', 'kg', 'Daging', true, true),
  ('Tetelan sapi', 'kg', 'Daging', true, true),
  ('Lemak sapi', 'kg', 'Daging', true, false),
  ('Tulang sapi', 'kg', 'Tulang', false, true),
  ('Tepung tapioka', 'kg', 'Tepung', true, false),
  ('Tepung sagu', 'kg', 'Tepung', true, false),
  ('Tepung terigu', 'kg', 'Tepung', true, true),
  ('Es batu', 'kg', 'Bahan produksi', true, false),
  ('Baking powder', 'kg', 'Bahan produksi', true, false),
  ('Garam', 'kg', 'Bumbu', true, true),
  ('Gula pasir', 'kg', 'Bumbu', true, true),
  ('Merica bubuk', 'kg', 'Bumbu', true, true),
  ('Bawang putih', 'kg', 'Bumbu', true, true),
  ('Bawang merah', 'kg', 'Bumbu', true, true),
  ('Penyedap rasa', 'kg', 'Bumbu', true, true),
  ('Jahe', 'kg', 'Bumbu', false, true),
  ('Kecap manis', 'botol', 'Bumbu', false, true),
  ('Kecap asin', 'botol', 'Bumbu', false, true),
  ('Saus tiram', 'botol', 'Bumbu', false, true),
  ('Mie telur', 'kg', 'Mie', false, true),
  ('Telur ayam', 'butir', 'Telur', false, true),
  ('Minyak goreng', 'liter', 'Minyak', false, true),
  ('Minyak ayam', 'liter', 'Minyak', false, true),
  ('Daun bawang', 'kg', 'Sayuran', false, true),
  ('Sawi hijau', 'kg', 'Sayuran', false, true),
  ('Seledri', 'kg', 'Sayuran', false, true),
  ('Tauge', 'kg', 'Sayuran', false, true),
  ('Kol', 'kg', 'Sayuran', false, true),
  ('Timun', 'kg', 'Sayuran', false, true),
  ('Selada', 'kg', 'Sayuran', false, true),
  ('Cabai merah', 'kg', 'Sayuran', false, true),
  ('Cabai rawit', 'kg', 'Sayuran', false, true),
  ('Bawang goreng', 'kg', 'Pelengkap', false, true),
  ('Jeruk limau', 'kg', 'Pelengkap', false, true),
  ('Saus sambal', 'botol', 'Saus & bumbu meja', false, true),
  ('Saus tomat', 'botol', 'Saus & bumbu meja', false, true),
  ('Cuka', 'botol', 'Saus & bumbu meja', false, true),
  ('Sambal', 'kg', 'Saus & bumbu meja', false, true),
  ('Mangkuk plastik', 'pcs', 'Kemasan', false, true),
  ('Bowl kertas', 'pcs', 'Kemasan', false, true),
  ('Plastik kresek', 'pcs', 'Kemasan', false, true),
  ('Kantong plastik', 'pcs', 'Kemasan', false, true),
  ('Sendok plastik', 'pcs', 'Kemasan', false, true),
  ('Garpu plastik', 'pcs', 'Kemasan', false, true),
  ('Sumpit', 'pasang', 'Kemasan', false, true),
  ('Tissue', 'pak', 'Kemasan', false, true),
  ('Cup minuman', 'pcs', 'Kemasan', false, true),
  ('Tutup cup', 'pcs', 'Kemasan', false, true),
  ('Plastik sambal', 'pcs', 'Kemasan', false, true),
  ('Label/stiker', 'pcs', 'Kemasan', false, true);

insert into public.items (name, kind, category, unit, untuk_produksi, ke_cabang)
select m.name, 'mentah', m.category, m.unit, m.untuk_produksi, m.ke_cabang
  from _master_barang m
 where not exists (select 1 from public.items i where i.kind = 'mentah' and lower(i.name) = lower(m.name));

-- Barang yang sudah ada tetap memakai satuan dan kategorinya; hanya jalurnya yang diseragamkan.
-- Barang siap jual (mis. air mineral) tidak disentuh.
update public.items i
   set untuk_produksi = m.untuk_produksi, ke_cabang = m.ke_cabang
  from _master_barang m
 where i.kind = 'mentah' and lower(i.name) = lower(m.name) and not i.siap_jual;

drop table if exists pg_temp._master_barang;

notify pgrst, 'reload schema';

-- Cek hasil (opsional):
--   select category, name, unit,
--          case when untuk_produksi and ke_cabang then 'dua' when ke_cabang then 'cabang' else 'olah' end as jalur
--     from public.items where kind = 'mentah' order by jalur, category, name;
