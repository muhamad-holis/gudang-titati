-- =====================================================================
-- GUDANG TITATI - UPDATE: PERMINTAAN CABANG TETAP BISA DIKIRIM WALAU STOK KOSONG
-- Saat gudang menekan Kirim pada Permintaan Cabang:
--   - stok cukup            : dikirim penuh seperti biasa
--   - stok kurang           : dikirim sebesar stok yang ada, baris ditandai (kosong = true)
--   - stok kosong           : jumlah dikirim 0, baris ditandai kosong; jumlah diminta tetap tersimpan
-- Stok gudang hanya dikurangi sebesar yang benar-benar dikirim.
-- Jenis dokumen lain (kirim ke cabang, kirim produksi, setoran) tetap menolak bila stok kurang.
--
-- JALANKAN SESUDAH supabase_update_kirim_cabang.sql (fungsi send_doc diganti).
-- Aman diulang. Jangan menjalankan ulang supabase_update_kirim_cabang.sql sesudah ini,
-- karena akan mengembalikan send_doc ke versi lama.
-- =====================================================================

alter table public.doc_lines add column if not exists qty_minta numeric;
alter table public.doc_lines add column if not exists kosong boolean not null default false;

-- jumlah dikirim boleh 0 (barang kosong)
alter table public.doc_lines drop constraint if exists doc_lines_qty_check;
alter table public.doc_lines add constraint doc_lines_qty_check check (qty >= 0);

create or replace function public.send_doc(p_doc uuid, p_lines jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.docs; v_role text := public.me_role(); r record; v_src text; have numeric;
  v_l jsonb; v_q numeric; v_old numeric; v_changed boolean := false; n_left int; n_kosong int := 0;
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

  -- cek stok: permintaan cabang yang stoknya kurang/kosong tetap jalan dan ditandai
  for r in select l.id, l.item_id, l.qty, l.role, i.name from public.doc_lines l join public.items i on i.id = l.item_id where l.doc_id = p_doc loop
    if d.type = 'setor_jadi' and r.role <> 'pakai' then continue; end if;
    select coalesce(sum(delta), 0) into have from public.stock_ledger where location = v_src and item_id = r.item_id;
    if have < r.qty then
      if d.type = 'minta_cabang' then
        update public.doc_lines
           set qty_minta = coalesce(qty_minta, qty), qty = greatest(have, 0), kosong = true
         where id = r.id;
        n_kosong := n_kosong + 1;
      else
        raise exception 'Stok % tidak cukup: tersedia %, dibutuhkan %', r.name, have, r.qty;
      end if;
    end if;
  end loop;

  for r in select l.item_id, l.qty, l.role from public.doc_lines l where l.doc_id = p_doc loop
    if d.type = 'setor_jadi' and r.role <> 'pakai' then continue; end if;
    if r.qty <= 0 then continue; end if;
    insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values (v_src, r.item_id, -r.qty, p_doc, public.me_name());
  end loop;

  update public.docs set status = 'dikirim', sent_at = now() where id = p_doc;
  perform public._log(p_doc, case when n_kosong > 0 then 'dikirim (' || n_kosong || ' barang kosong/kurang)' else 'dikirim' end, '');
end $$;
