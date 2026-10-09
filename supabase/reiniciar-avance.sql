-- Escuela de Ministros · Permite que cada ministro reinicie SU propio avance (incluido el examen)
-- Pega en Supabase → SQL Editor → Run. Se puede correr varias veces.
create or replace function public.avance_reiniciar(p_codigo text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.ministros;
begin
  r := public._yo(p_codigo);
  update public.ministros set avance = '{}'::jsonb, examen = 0, modulos = 0, actualizado = now() where id = r.id;
end $$;
revoke all on function public.avance_reiniciar(text) from public;
grant execute on function public.avance_reiniciar(text) to anon;
