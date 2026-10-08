-- =========================================================
-- Escuela de Ministros · Notificaciones en el celular
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- (Se corre después de activar-todo.sql. Se puede correr varias veces.)
-- =========================================================

create table if not exists public.push_subs (
  endpoint text primary key check (char_length(endpoint) between 10 and 600),
  ministro_id uuid not null references public.ministros(id) on delete cascade,
  p256dh text not null check (char_length(p256dh) <= 200),
  auth text not null check (char_length(auth) <= 100),
  creado timestamptz not null default now()
);
create index if not exists push_subs_ministro on public.push_subs(ministro_id);
alter table public.push_subs enable row level security;
revoke all on public.push_subs from anon, authenticated;

-- Cada quien guarda o quita el permiso de SU celular
create or replace function public.push_guardar(p_codigo text, p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.ministros;
begin
  r := public._yo(p_codigo);
  if p_endpoint !~ '^https://' then raise exception 'Suscripción no válida' using errcode = 'P0001'; end if;
  insert into public.push_subs(endpoint, ministro_id, p256dh, auth) values (p_endpoint, r.id, p_p256dh, p_auth)
  on conflict (endpoint) do update set ministro_id = excluded.ministro_id, p256dh = excluded.p256dh, auth = excluded.auth, creado = now();
  -- máximo 5 celulares por persona
  delete from public.push_subs where ministro_id = r.id and endpoint not in
    (select endpoint from public.push_subs where ministro_id = r.id order by creado desc limit 5);
end $$;

create or replace function public.push_quitar(p_codigo text, p_endpoint text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.ministros;
begin
  r := public._yo(p_codigo);
  delete from public.push_subs where endpoint = p_endpoint and ministro_id = r.id;
end $$;

-- Solo coordinador o padre: a quién avisar de un turno asignado
create or replace function public.push_turno(p_codigo text, p_turno uuid, p_ministro uuid) returns json
language plpgsql security definer set search_path = public as $$
declare r public.ministros; t public.turnos;
begin
  r := public._coord(p_codigo);
  select * into t from public.turnos where id = p_turno;
  if t.id is null or not exists(select 1 from public.inscripciones where turno_id = p_turno and ministro_id = p_ministro) then
    raise exception 'Ese ministro no está en el turno' using errcode = 'P0001';
  end if;
  return json_build_object(
    'tipo', t.tipo, 'fecha', t.fecha, 'hora', t.hora, 'lugar', t.lugar, 'de', r.nombre,
    'subs', coalesce((select json_agg(json_build_object('endpoint', endpoint, 'p256dh', p256dh, 'auth', auth))
                      from public.push_subs where ministro_id = p_ministro), '[]'::json));
end $$;

-- Solo coordinador o padre: el último aviso y todos los celulares activos
create or replace function public.push_aviso(p_codigo text) returns json
language plpgsql security definer set search_path = public as $$
declare r public.ministros; a public.avisos;
begin
  r := public._coord(p_codigo);
  select * into a from public.avisos order by creado desc limit 1;
  if a.id is null or a.creado < now() - interval '10 minutes' then raise exception 'No hay aviso nuevo' using errcode = 'P0001'; end if;
  return json_build_object(
    'titulo', a.titulo, 'texto', a.texto, 'de', r.nombre,
    'subs', coalesce((select json_agg(json_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth))
                      from public.push_subs s join public.ministros m on m.id = s.ministro_id
                      where m.activo and m.id <> r.id), '[]'::json));
end $$;

-- Solo coordinador o padre: borrar celulares que ya no existen
create or replace function public.push_limpiar(p_codigo text, p_endpoints text[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._coord(p_codigo);
  delete from public.push_subs where endpoint = any(p_endpoints);
end $$;

revoke all on function public.push_guardar(text,text,text,text), public.push_quitar(text,text),
  public.push_turno(text,uuid,uuid), public.push_aviso(text), public.push_limpiar(text,text[]) from public;
grant execute on function public.push_guardar(text,text,text,text), public.push_quitar(text,text),
  public.push_turno(text,uuid,uuid), public.push_aviso(text), public.push_limpiar(text,text[]) to anon;
