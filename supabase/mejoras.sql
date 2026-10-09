-- =========================================================
-- Escuela de Ministros · Confirmar asistencia y recordatorio automático
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- (Se corre después de notificaciones.sql. Se puede correr varias veces.)
-- =========================================================

alter table public.inscripciones add column if not exists confirma text check (confirma in ('si','no'));
alter table public.inscripciones add column if not exists confirma_en timestamptz;

create table if not exists public.config (k text primary key, v text not null);
alter table public.config enable row level security;
revoke all on public.config from anon, authenticated;
-- Huella (sha256) de la clave del recordatorio. La clave real solo vive en Vercel (CRON_SECRET).
insert into public.config(k, v) values ('recordatorio', 'd7482d2e715c9c7000b97427f560dfc27651f803c37e5d9d4f90049a42377cf1')
  on conflict (k) do update set v = excluded.v;

-- Rol de servicio: ahora incluye si cada quien confirmó
create or replace function public.turnos_lista(p_codigo text) returns json
language plpgsql security definer set search_path = public as $$
declare r public.ministros; c boolean;
begin
  r := public._yo(p_codigo);
  c := r.rol in ('coordinador','padre');
  return coalesce((select json_agg(json_build_object(
      'id', t.id, 'fecha', t.fecha, 'hora', t.hora, 'tipo', t.tipo, 'lugar', t.lugar, 'cupo', t.cupo, 'notas', t.notas,
      'anotados', coalesce((select json_agg(m.nombre order by i.creado) from public.inscripciones i join public.ministros m on m.id = i.ministro_id where i.turno_id = t.id), '[]'::json),
      'anot', case when c then coalesce((select json_agg(json_build_object('id', m.id, 'nombre', m.nombre, 'conf', i.confirma) order by i.creado) from public.inscripciones i join public.ministros m on m.id = i.ministro_id where i.turno_id = t.id), '[]'::json) else null end,
      'yo', exists(select 1 from public.inscripciones i where i.turno_id = t.id and i.ministro_id = r.id),
      'conf', (select i.confirma from public.inscripciones i where i.turno_id = t.id and i.ministro_id = r.id),
      'asignado', (select a.nombre from public.inscripciones i join public.ministros a on a.id = i.asignado_por where i.turno_id = t.id and i.ministro_id = r.id and i.asignado_por <> r.id)
    ) order by t.fecha, t.hora)
    from public.turnos t where t.fecha >= (now() at time zone 'America/Mexico_City')::date), '[]'::json);
end $$;

-- Cada ministro confirma su propio turno: 'si', 'no' o null (sin respuesta)
create or replace function public.turno_confirmar(p_codigo text, p_turno uuid, p_estado text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.ministros;
begin
  r := public._yo(p_codigo);
  if p_estado is not null and p_estado not in ('si','no') then raise exception 'Respuesta no válida' using errcode = 'P0001'; end if;
  update public.inscripciones set confirma = p_estado, confirma_en = now() where turno_id = p_turno and ministro_id = r.id;
  if not found then raise exception 'No estás en ese turno' using errcode = 'P0001'; end if;
end $$;

-- Cuando alguien dice "No puedo": avisar al padre y coordinadores
create or replace function public.push_baja(p_codigo text, p_turno uuid) returns json
language plpgsql security definer set search_path = public as $$
declare r public.ministros; t public.turnos;
begin
  r := public._yo(p_codigo);
  if not exists(select 1 from public.inscripciones where turno_id = p_turno and ministro_id = r.id and confirma = 'no' and confirma_en > now() - interval '10 minutes') then
    raise exception 'Nada que avisar' using errcode = 'P0001';
  end if;
  select * into t from public.turnos where id = p_turno;
  return json_build_object('tipo', t.tipo, 'fecha', t.fecha, 'hora', t.hora, 'nombre', r.nombre,
    'subs', coalesce((select json_agg(json_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth))
                      from public.push_subs s join public.ministros m on m.id = s.ministro_id
                      where m.activo and m.rol in ('coordinador','padre') and m.id <> r.id), '[]'::json));
end $$;

-- Recordatorio diario (lo llama Vercel una vez al día con la clave secreta)
create or replace function public.push_recordatorios(p_clave text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare manana date := (now() at time zone 'America/Mexico_City')::date + 1;
begin
  if coalesce(p_clave,'') = '' or encode(extensions.digest(p_clave, 'sha256'), 'hex') is distinct from (select v from public.config where k = 'recordatorio') then
    raise exception 'Clave no válida' using errcode = 'P0001';
  end if;
  return coalesce((select json_agg(json_build_object('tipo', t.tipo, 'fecha', t.fecha, 'hora', t.hora, 'lugar', t.lugar, 'turno', t.id,
      'subs', (select json_agg(json_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth)) from public.push_subs s where s.ministro_id = i.ministro_id)))
    from public.inscripciones i join public.turnos t on t.id = i.turno_id join public.ministros m on m.id = i.ministro_id
    where t.fecha = manana and m.activo and i.confirma is distinct from 'no'
      and exists(select 1 from public.push_subs s where s.ministro_id = i.ministro_id)), '[]'::json);
end $$;

revoke all on function public.turno_confirmar(text,uuid,text), public.push_baja(text,uuid), public.push_recordatorios(text) from public;
grant execute on function public.turno_confirmar(text,uuid,text), public.push_baja(text,uuid), public.push_recordatorios(text) to anon;
