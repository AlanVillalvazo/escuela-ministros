-- =========================================================
-- Escuela de Ministros · Agregar el rol "Padre"
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- El Padre tiene los mismos permisos que el coordinador.
-- =========================================================

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
