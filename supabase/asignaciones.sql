-- =========================================================
-- Escuela de Ministros · El padre o el coordinador asignan turnos
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- =========================================================

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
