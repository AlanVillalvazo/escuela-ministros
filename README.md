# Escuela de Ministros · Sagrado Corazón de Jesús, El Cercado

Página de formación para los Ministros Extraordinarios de la Sagrada Comunión.
Se publica en Vercel: https://escuela-de-ministros.vercel.app

## Archivos
- `index.html` — toda la página.
- `config.js` — datos de conexión con Supabase (URL del proyecto y clave pública *anon*).
- `sw.js`, `manifest.webmanifest`, `icon-*.png` — permiten instalarla como app y abrirla sin señal.
- `vercel.json` — evita que el celular guarde versiones viejas de `sw.js` y `config.js`.

## Cómo funciona el acceso
- Cada ministro entra con un **código** que le da el coordinador (Equipo → Ministros y códigos).
- Su avance (módulos, quizzes, examen) se guarda en su cuenta y se ve igual en cualquier aparato.
- Sin código se puede estudiar todo; el avance se queda solo en ese celular.
- La base de datos solo se usa a través de funciones protegidas: nadie puede leer las tablas directamente.
