-- =========================================================
-- Escuela de Ministros · Avisos del coordinador
-- Pega TODO este archivo en Supabase → SQL Editor → Run.
-- (Necesita que ya se haya corrido el archivo principal.)
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
