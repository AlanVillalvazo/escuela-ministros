// Envía notificaciones al celular cuando el padre o el coordinador asigna un turno o publica un aviso.
// Supabase revisa que quien lo pide sea coordinador o padre y devuelve el texto y a quién mandarlo.
// La clave privada VAPID vive en Vercel → Settings → Environment Variables (VAPID_PRIVATE_KEY). Nunca en el código.
const webpush = require("web-push");

const SB_URL = process.env.SUPABASE_URL || "https://iocohrbetyqxontllazt.supabase.co";
const SB_KEY = process.env.SUPABASE_ANON_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlvY29ocmJldHlxeG9udGxsYXp0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEzODQzNTUsImV4cCI6MjEwNjk2MDM1NX0.lxqgQF1BPepI6ULHHXFJ9nmCD8mco1c_8teC7pP8GNM";
const VAPID_PUBLIC = process.env.VAPID_PUBLIC_KEY || "BJCKrk6uexkcYnkvhsSKf6rWwf_rZuGHuFwij6m4NbKj5etrXoF0gWjYrmQBJ8dr2c2KdnR9ZpyajAyTj9T7GsA";
const UUID = /^[0-9a-f-]{36}$/i;

async function rpc(fn, args) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(args)
  });
  const t = await r.text();
  let j = null; try { j = t ? JSON.parse(t) : null; } catch (e) {}
  if (!r.ok) { const e = new Error((j && j.message) || "Error de Supabase"); e.status = r.status; throw e; }
  return j;
}

function fechaBonita(f, h) {
  const d = new Date(f + "T12:00:00");
  const s = d.toLocaleDateString("es-MX", { weekday: "long", day: "numeric", month: "long", timeZone: "America/Mexico_City" });
  return s.charAt(0).toUpperCase() + s.slice(1) + (h ? " · " + h : "");
}

module.exports = async (req, res) => {
  if (req.method !== "POST") { res.status(405).json({ error: "Solo POST" }); return; }
  const priv = process.env.VAPID_PRIVATE_KEY;
  if (!priv) { res.status(503).json({ error: "Falta configurar VAPID_PRIVATE_KEY en Vercel" }); return; }
  let b = req.body;
  if (typeof b === "string") { try { b = JSON.parse(b); } catch (e) { b = {}; } }
  b = b || {};
  const codigo = String(b.codigo || "").slice(0, 40);
  if (!codigo) { res.status(400).json({ error: "Falta el código" }); return; }

  let info, msg;
  try {
    if (b.tipo === "turno") {
      if (!UUID.test(b.turno || "") || !UUID.test(b.ministro || "")) { res.status(400).json({ error: "Datos no válidos" }); return; }
      info = await rpc("push_turno", { p_codigo: codigo, p_turno: b.turno, p_ministro: b.ministro });
      msg = { title: "Te asignaron un servicio", body: `${info.tipo} · ${fechaBonita(info.fecha, info.hora)}${info.lugar ? " · " + info.lugar : ""}. Te asignó: ${info.de}.`, url: "/#inicio", tag: "turno-" + b.turno };
    } else if (b.tipo === "aviso") {
      info = await rpc("push_aviso", { p_codigo: codigo });
      msg = { title: "Aviso: " + info.titulo, body: (info.texto || "Abre la app para verlo.").slice(0, 180), url: "/#avisos", tag: "aviso" };
    } else { res.status(400).json({ error: "Tipo no válido" }); return; }
  } catch (e) {
    res.status(e.status === 404 ? 501 : 403).json({ error: e.message }); return;
  }

  webpush.setVapidDetails("https://escuela-de-ministros.vercel.app", VAPID_PUBLIC, priv);
  const subs = (info && info.subs) || [];
  const gone = [];
  let sent = 0;
  await Promise.all(subs.map(s =>
    webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(msg), { TTL: 60 * 60 * 24 * 3, urgency: "high" })
      .then(() => { sent++; })
      .catch(e => { if (e && (e.statusCode === 404 || e.statusCode === 410)) gone.push(s.endpoint); })
  ));
  if (gone.length) { try { await rpc("push_limpiar", { p_codigo: codigo, p_endpoints: gone }); } catch (e) {} }
  res.status(200).json({ enviadas: sent, total: subs.length });
};
