-- =========================================================
-- Escuela de Ministros · ACTIVAR TODO (avisos + rol Padre + asignaciones)
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- Se puede correr las veces que quieras sin perder datos.
-- =========================================================


create table if not exists public.avisos (
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (char_length(titulo) between 1 and 80),
  texto text not null default '' check (char_length(texto) <= 600),
  autor uuid references public.ministros(id) on delete set null,
  creado timestamptz not null default now()
);
alter table public.avisos enable row level security;
revoke all on public.avisos from anon, authenticated;

create or replace function public.avisos_lista(p_codigo text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform public._yo(p_codigo);
  return coalesce((select json_agg(json_build_object('id', a.id, 'titulo', a.titulo, 'texto', a.texto, 'creado', a.creado, 'autor', m.nombre) order by a.creado desc)
    from (select * from public.avisos where creado > now() - interval '60 days' order by creado desc limit 20) a
    left join public.ministros m on m.id = a.autor), '[]'::json);
end $$;

create or replace function public.aviso_crear(p_codigo text, p_titulo text, p_texto text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.ministros;
begin
  r := public._coord(p_codigo);
  if char_length(trim(coalesce(p_titulo,''))) = 0 then raise exception 'Escribe el título del aviso' using errcode = 'P0001'; end if;
  insert into public.avisos(titulo, texto, autor) values (left(trim(p_titulo),80), left(trim(coalesce(p_texto,'')),600), r.id);
end $$;

create or replace function public.aviso_borrar(p_codigo text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._coord(p_codigo);
  delete from public.avisos where id = p_id;
end $$;

revoke all on function public.avisos_lista(text), public.aviso_crear(text,text,text), public.aviso_borrar(text,uuid) from public;
grant execute on function public.avisos_lista(text), public.aviso_crear(text,text,text), public.aviso_borrar(text,uuid) to anon;


alter table public.ministros drop constraint if exists ministros_rol_check;
alter table public.ministros add constraint ministros_rol_check check (rol in ('ministro','coordinador','padre'));

create or replace function public._coord(p_codigo text) returns public.ministros
language plpgsql security definer set search_path = public as $$
declare r public.ministros;
begin
  r := public._yo(p_codigo);
  if r.rol not in ('coordinador','padre') then raise exception 'Solo el coordinador o el padre pueden hacer esto' using errcode = 'P0001'; end if;
  return r;
end $$;
revoke all on function public._coord(text) from public, anon, authenticated;

create or replace function public.equipo(p_codigo text) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform public._yo(p_codigo);
  return coalesce((select json_agg(json_build_object('nombre', nombre, 'examen', examen, 'modulos', modulos, 'actualizado', actualizado) order by examen desc, modulos desc, nombre)
    from public.ministros where activo and rol <> 'padre'), '[]'::json);
end $$;

create or replace function public.ministro_alta(p_codigo text, p_nombre text, p_nuevo_codigo text, p_rol text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._coord(p_codigo);
  if char_length(trim(coalesce(p_nuevo_codigo,''))) < 6 then raise exception 'El código debe tener al menos 6 caracteres' using errcode = 'P0001'; end if;
  if exists(select 1 from public.ministros where codigo_hash = public._hash(p_nuevo_codigo)) then
    raise exception 'Ese código ya está en uso; genera otro' using errcode = 'P0001';
  end if;
  insert into public.ministros(nombre, codigo_hash, rol)
  values (trim(p_nombre), public._hash(p_nuevo_codigo), case when p_rol in ('coordinador','padre') then p_rol else 'ministro' end);
end $$;


alter table public.inscripciones add column if not exists asignado_por uuid references public.ministros(id) on delete set null;

create or replace function public.turnos_lista(p_codigo text) returns json
language plpgsql security definer set search_path = public as $$
declare r public.ministros; c boolean;
begin
  r := public._yo(p_codigo);
  c := r.rol in ('coordinador','padre');
  return coalesce((select json_agg(json_build_object(
      'id', t.id, 'fecha', t.fecha, 'hora', t.hora, 'tipo', t.tipo, 'lugar', t.lugar, 'cupo', t.cupo, 'notas', t.notas,
      'anotados', coalesce((select json_agg(m.nombre order by i.creado) from public.inscripciones i join public.ministros m on m.id = i.ministro_id where i.turno_id = t.id), '[]'::json),
      'anot', case when c then coalesce((select json_agg(json_build_object('id', m.id, 'nombre', m.nombre) order by i.creado) from public.inscripciones i join public.ministros m on m.id = i.ministro_id where i.turno_id = t.id), '[]'::json) else null end,
      'yo', exists(select 1 from public.inscripciones i where i.turno_id = t.id and i.ministro_id = r.id),
      'asignado', (select a.nombre from public.inscripciones i join public.ministros a on a.id = i.asignado_por where i.turno_id = t.id and i.ministro_id = r.id and i.asignado_por <> r.id)
    ) order by t.fecha, t.hora)
    from public.turnos t where t.fecha >= (now() at time zone 'America/Mexico_City')::date), '[]'::json);
end $$;

create or replace function public.turno_asignar(p_codigo text, p_turno uuid, p_ministro uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.ministros; cu int; n int;
begin
  r := public._coord(p_codigo);
  select cupo into cu from public.turnos where id = p_turno for update;
  if cu is null then raise exception 'El turno ya no existe' using errcode = 'P0001'; end if;
  if not exists(select 1 from public.ministros where id = p_ministro and activo) then raise exception 'Ese ministro no está activo' using errcode = 'P0001'; end if;
  if exists(select 1 from public.inscripciones where turno_id = p_turno and ministro_id = p_ministro) then return; end if;
  select count(*) into n from public.inscripciones where turno_id = p_turno;
  if n >= cu then raise exception 'El turno ya está completo; aumenta el número de ministros necesarios' using errcode = 'P0001'; end if;
  insert into public.inscripciones(turno_id, ministro_id, asignado_por) values (p_turno, p_ministro, r.id);
end $$;

create or replace function public.turno_desasignar(p_codigo text, p_turno uuid, p_ministro uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._coord(p_codigo);
  delete from public.inscripciones where turno_id = p_turno and ministro_id = p_ministro;
end $$;

revoke all on function public.turno_asignar(text,uuid,uuid), public.turno_desasignar(text,uuid,uuid) from public;
grant execute on function public.turno_asignar(text,uuid,uuid), public.turno_desasignar(text,uuid,uuid) to anon;

