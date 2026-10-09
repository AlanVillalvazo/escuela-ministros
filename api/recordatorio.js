// Vercel lo llama solo una vez al día (ver "crons" en vercel.json).
// Avisa a cada ministro que tiene servicio MAÑANA. Necesita CRON_SECRET en Vercel.
const webpush = require("web-push");
const SB_URL = process.env.SUPABASE_URL || "https://iocohrbetyqxontllazt.supabase.co";
const SB_KEY = process.env.SUPABASE_ANON_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlvY29ocmJldHlxeG9udGxsYXp0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEzODQzNTUsImV4cCI6MjEwNjk2MDM1NX0.lxqgQF1BPepI6ULHHXFJ9nmCD8mco1c_8teC7pP8GNM";
const VAPID_PUBLIC = process.env.VAPID_PUBLIC_KEY || "BJCKrk6uexkcYnkvhsSKf6rWwf_rZuGHuFwij6m4NbKj5etrXoF0gWjYrmQBJ8dr2c2KdnR9ZpyajAyTj9T7GsA";

module.exports = async (req, res) => {
  const secret = process.env.CRON_SECRET, priv = process.env.VAPID_PRIVATE_KEY;
  if (!secret || req.headers.authorization !== `Bearer ${secret}`) { res.status(401).json({ error: "No autorizado" }); return; }
  if (!priv) { res.status(503).json({ error: "Falta VAPID_PRIVATE_KEY" }); return; }
  const r = await fetch(`${SB_URL}/rest/v1/rpc/push_recordatorios`, {
    method: "POST",
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_clave: secret })
  });
  if (!r.ok) { res.status(502).json({ error: "Supabase: " + r.status }); return; }
  const list = (await r.json()) || [];
  webpush.setVapidDetails("https://escuela-de-ministros.vercel.app", VAPID_PUBLIC, priv);
  let sent = 0;
  await Promise.all(list.flatMap(t => (t.subs || []).map(s => {
    const msg = { title: "Mañana te toca servir", body: `${t.tipo}${t.hora ? " · " + t.hora : ""}${t.lugar ? " · " + t.lugar : ""}. Recuerda: en gracia de Dios y una hora de ayuno.`, url: "/#inicio", tag: "rec-" + t.turno };
    return webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(msg), { TTL: 60 * 60 * 12 }).then(() => { sent++; }).catch(() => {});
  })));
  res.status(200).json({ servicios: list.length, enviadas: sent });
};
