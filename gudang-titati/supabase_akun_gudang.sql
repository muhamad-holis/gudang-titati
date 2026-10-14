-- =====================================================================
-- ATUR PERAN 6 AKUN. Jalankan SETELAH membuat 6 akun di
-- Supabase -> Authentication -> Users -> Add user (centang Auto Confirm User).
-- Email di bawah boleh diganti sesuai akun yang Anda buat.
-- =====================================================================
do $$
declare
  v_email  text[] := array['owner@titati.com', 'gudang@titati.com', 'produksi@titati.com', 'ciomas@titati.com', 'ciracas@titati.com', 'ciruas@titati.com'];
  v_role   text[] := array['owner', 'gudang', 'produksi', 'cabang', 'cabang', 'cabang'];
  v_name   text[] := array['Owner', 'Kepala Gudang', 'Kepala Produksi', 'Cabang Ciomas', 'Cabang Ciracas', 'Cabang Ciruas'];
  v_branch text[] := array['', '', '', 'Cabang Ciomas', 'Cabang Ciracas', 'Cabang Ciruas'];
  i int; v_id uuid;
begin
  for i in 1..6 loop
    select id into v_id from auth.users where lower(email) = lower(v_email[i]);
    if v_id is null then raise exception 'Akun % belum dibuat di Authentication > Users', v_email[i]; end if;
    insert into public.profiles (id, name, role, branch) values (v_id, v_name[i], v_role[i], v_branch[i])
    on conflict (id) do update set name = excluded.name, role = excluded.role, branch = excluded.branch;
  end loop;
end $$;

-- CEK: harus muncul 6 baris dengan peran yang benar
select u.email, p.name, p.role, p.branch from auth.users u join public.profiles p on p.id = u.id order by p.role, u.email;
