-- =====================================================================
-- GUDANG TITATI - UPDATE: HARGA JUAL STANDAR PER BARANG + BAHAN JADI BOLEH TANPA HARGA
--
-- 1. Kolom items.sell_price_default: harga jual standar ke cabang per barang (0 = belum diatur).
--    Diisi di Master / Barang (ubah barang). Aplikasi memakainya sebagai isian awal harga jual
--    saat Kirim ke Cabang dan saat mengirim Permintaan Cabang. Boleh diubah tiap transaksi.
-- 2. Kirim ke Cabang: barang jenis BAHAN JADI (mis. bakso hasil produksi) boleh dikirim tanpa
--    harga jual. Harganya diisi nanti lewat tombol "Atur harga jual" (fungsi atur_harga_jual,
--    sudah ada). Barang selain bahan jadi tetap wajib berharga jual.
--    Bila harga jual tidak dikirim, dipakai harga jual standar barang (bila ada).
--
-- JALANKAN SETELAH supabase_update_omzet_tagihan.sql. Aman diulang.
-- JANGAN menjalankan ulang supabase_update_omzet_tagihan.sql sesudah file ini, karena
-- create_kirim_cabang akan kembali ke versi lama (harga jual wajib untuk semua barang).
-- =====================================================================

alter table public.items add column if not exists sell_price_default numeric not null default 0;
alter table public.items drop constraint if exists items_sell_price_default_check;
alter table public.items add constraint items_sell_price_default_check check (sell_price_default >= 0);

create or replace function public.create_kirim_cabang(p_cabang text, p_note text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_l jsonb; v_sell numeric; v_item uuid; v_kind text; v_std numeric; v_name text;
begin
  if public.me_role() <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh mengirim ke cabang'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Isi minimal satu barang';
  end if;
  -- cek harga: wajib, kecuali bahan jadi (harga standar dipakai bila ada)
  for v_l in select value from jsonb_array_elements(p_lines) loop
    v_item := (v_l->>'item_id')::uuid;
    v_sell := coalesce(nullif(v_l->>'sell_price', '')::numeric, 0);
    select kind, sell_price_default, name into v_kind, v_std, v_name from public.items where id = v_item;
    if not found then raise exception 'Barang tidak ditemukan'; end if;
    if v_sell <= 0 and coalesce(v_std, 0) <= 0 and v_kind <> 'jadi' then
      raise exception 'Harga jual wajib diisi untuk %', v_name;
    end if;
  end loop;

  v_id := public.create_doc('kirim_cabang', p_cabang, p_note, p_lines);

  for v_l in select value from jsonb_array_elements(p_lines) loop
    v_item := (v_l->>'item_id')::uuid;
    v_sell := coalesce(nullif(v_l->>'sell_price', '')::numeric, 0);
    if v_sell <= 0 then
      select coalesce(sell_price_default, 0) into v_sell from public.items where id = v_item;
    end if;
    update public.doc_lines
       set sell_price = v_sell
     where doc_id = v_id and item_id = v_item;
  end loop;
  perform public._log(v_id, 'harga jual diisi gudang', '');
  return v_id;
end $$;
