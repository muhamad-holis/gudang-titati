-- =====================================================================
-- GUDANG TITATI - UPDATE: KOREKSI HARGA BARANG MASUK
-- Untuk memperbaiki harga satuan yang salah input pada Barang Masuk yang SUDAH tersimpan
-- (mis. Saos Sb 110 seharusnya 110000).
--
-- Aturan:
--  - owner : boleh mengoreksi Barang Masuk kapan saja.
--  - gudang: hanya selama pembelian belum diverifikasi owner. Setelah dikoreksi gudang,
--            status verifikasi kembali "menunggu" supaya owner memeriksa ulang.
--  - alasan koreksi wajib; harga lama -> baru tercatat di Riwayat dokumen.
--  - jumlah/stok TIDAK berubah, hanya harga.
-- Efek: nilai stok gudang dan harga rata-rata ikut benar (dihitung dari harga masuk).
--       Harga pada bon cabang untuk barang yang dikoreksi dihitung ulang dari harga rata-rata baru.
-- Tidak mengganti fungsi lama. Aman diulang.
-- =====================================================================

create or replace function public.koreksi_harga_masuk(p_doc uuid, p_lines jsonb, p_alasan text) returns text
language plpgsql security definer set search_path = public as $$
declare
  d public.docs; v_role text := public.me_role(); v_l jsonb; v_harga numeric; r public.doc_lines;
  n_ubah int := 0; n_bon int := 0; v_detail text := ''; v_nama text; v_old text; v_new text; ids uuid[] := '{}';
begin
  if v_role not in ('owner', 'gudang') then raise exception 'Hanya owner atau kepala gudang yang boleh mengoreksi harga'; end if;
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.type <> 'masuk' or d.status <> 'diterima' then raise exception 'Hanya Barang Masuk yang sudah tersimpan yang bisa dikoreksi harganya'; end if;
  if v_role = 'gudang' and d.verif = 'ok' then raise exception 'Pembelian ini sudah diverifikasi owner. Minta owner yang mengoreksi.'; end if;
  if length(trim(coalesce(p_alasan, ''))) < 3 then raise exception 'Alasan koreksi wajib diisi'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'Tidak ada perubahan harga'; end if;

  for v_l in select value from jsonb_array_elements(p_lines) loop
    v_harga := (v_l->>'unit_price')::numeric;
    if v_harga is null or v_harga <= 0 then raise exception 'Harga harus lebih dari 0'; end if;
    select * into r from public.doc_lines where id = (v_l->>'line_id')::uuid and doc_id = p_doc;
    if not found then continue; end if;
    if r.unit_price = v_harga then continue; end if;
    select name into v_nama from public.items where id = r.item_id;
    v_old := regexp_replace(to_char(r.unit_price, 'FM999999999990.99'), '\.$', '');
    v_new := regexp_replace(to_char(v_harga, 'FM999999999990.99'), '\.$', '');
    update public.doc_lines set unit_price = v_harga where id = r.id;
    v_detail := v_detail || case when v_detail = '' then '' else '; ' end || v_nama || ' ' || v_old || ' -> ' || v_new;
    ids := array_append(ids, r.item_id);
    n_ubah := n_ubah + 1;
  end loop;
  if n_ubah = 0 then raise exception 'Tidak ada harga yang berubah'; end if;

  -- harga terkunci di bon cabang untuk barang yang dikoreksi dihitung ulang
  update public.doc_lines dl
     set unit_price = public._harga_rata(dl.item_id, coalesce(c.sent_at, c.created_at))
    from public.docs c
   where c.id = dl.doc_id and c.type in ('minta_cabang', 'kirim_cabang')
     and c.status in ('dikirim', 'diterima') and dl.item_id = any(ids);
  get diagnostics n_bon = row_count;

  if v_role = 'gudang' and d.verif in ('menunggu', 'tolak') then
    update public.docs set verif = 'menunggu' where id = p_doc;
  end if;

  perform public._log(p_doc, 'harga dikoreksi', v_detail || ' | alasan: ' || trim(p_alasan));
  return 'ok:' || n_ubah || ':' || n_bon;
end $$;

revoke execute on function public.koreksi_harga_masuk(uuid, jsonb, text) from public, anon;
grant execute on function public.koreksi_harga_masuk(uuid, jsonb, text) to authenticated;
