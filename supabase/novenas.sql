-- =========================================================
-- Escuela de Ministros · Recordatorio diario de las novenas
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- (Se corre después de notificaciones.sql y mejoras.sql. Se puede correr varias veces.)
-- La intención de cada persona NO se guarda aquí: se queda solo en su celular.
-- =========================================================

create table if not exists public.novenas_rec (
  ministro_id uuid not null references public.ministros(id) on delete cascade,
  novena text not null check (novena ~ '^[a-z]{2,20}$'),
  nombre text not null check (char_length(nombre) between 3 and 80),
  dia int not null default 0 check (dia between 0 and 9),
  ultima date,
  activa boolean not null default true,
  actualizado timestamptz not null default now(),
  primary key (ministro_id, novena)
);
alter table public.novenas_rec enable row level security;
revoke all on public.novenas_rec from anon, authenticated;

-- Cada quien guarda cómo va SU novena (cuántos días lleva y cuándo rezó por última vez)
create or replace function public.novena_guardar(p_codigo text, p_novena text, p_nombre text, p_dia int, p_ultima date, p_activa boolean) returns void
language plpgsql security definer set search_path = public as $$
declare r public.ministros;
begin
  r := public._yo(p_codigo);
  if p_novena !~ '^[a-z]{2,20}$' or coalesce(p_dia, -1) not between 0 and 9 then
    raise exception 'Datos no válidos' using errcode = 'P0001';
  end if;
  if not coalesce(p_activa, false) or p_dia >= 9 then
    delete from public.novenas_rec where ministro_id = r.id and novena = p_novena;
    return;
  end if;
  insert into public.novenas_rec(ministro_id, novena, nombre, dia, ultima, activa, actualizado)
  values (r.id, p_novena, left(coalesce(p_nombre, 'Novena'), 80), p_dia, p_ultima, true, now())
  on conflict (ministro_id, novena) do update
    set nombre = excluded.nombre, dia = excluded.dia, ultima = excluded.ultima, activa = true, actualizado = now();
  -- máximo 5 novenas a la vez por persona
  delete from public.novenas_rec where ministro_id = r.id and novena not in
    (select novena from public.novenas_rec where ministro_id = r.id order by actualizado desc limit 5);
end $$;

-- Solo el recordatorio diario (con la clave secreta): a quién toca recordarle su novena hoy.
-- No se le recuerda a quien ya rezó hoy, ni a quien la dejó de rezar hace más de 3 días.
create or replace function public.push_novenas(p_clave text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare hoy date := (now() at time zone 'America/Mexico_City')::date;
begin
  if coalesce(p_clave,'') = '' or encode(extensions.digest(p_clave, 'sha256'), 'hex') is distinct from (select v from public.config where k = 'recordatorio') then
    raise exception 'Clave no válida' using errcode = 'P0001';
  end if;
  delete from public.novenas_rec where coalesce(ultima, actualizado::date) < hoy - 3;
  return coalesce((select json_agg(json_build_object('novena', n.novena, 'nombre', n.nombre, 'dia', n.dia + 1, 'ministro', n.ministro_id,
      'subs', (select json_agg(json_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth)) from public.push_subs s where s.ministro_id = n.ministro_id)))
    from public.novenas_rec n join public.ministros m on m.id = n.ministro_id
    where n.activa and n.dia < 9 and (n.ultima is null or n.ultima < hoy) and m.activo
      and exists(select 1 from public.push_subs s where s.ministro_id = n.ministro_id)), '[]'::json);
end $$;

revoke all on function public.novena_guardar(text,text,text,int,date,boolean), public.push_novenas(text) from public;
grant execute on function public.novena_guardar(text,text,text,int,date,boolean), public.push_novenas(text) to anon;
