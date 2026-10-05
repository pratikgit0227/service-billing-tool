// Supabase Edge Function: serves open to-do tasks as an iCalendar (.ics) feed for Google Calendar.
// URL: https://<project-ref>.supabase.co/functions/v1/calendar?t=<secret token>
// The token is created in the app (To-do -> Live calendar feed) and stored in meta row id='calendar'.
// Deploy with "Verify JWT" turned OFF (Google Calendar cannot send a login), the secret token is the protection.
import { createClient } from "jsr:@supabase/supabase-js@2";

const esc = (x: string) => String(x).replace(/\\/g, "\\\\").replace(/[,;]/g, (m) => "\\" + m).replace(/\r?\n/g, "\\n");
const ymd = (d: string) => d.replace(/-/g, "");
const nextDay = (d: string) => {
  const t = new Date(d + "T00:00:00Z");
  t.setUTCDate(t.getUTCDate() + 1);
  return t.toISOString().slice(0, 10).replace(/-/g, "");
};

Deno.serve(async (req) => {
  const token = new URL(req.url).searchParams.get("t") ?? "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { data: cfg } = await sb.from("meta").select("data").eq("id", "calendar").maybeSingle();
  if (!token || !cfg || cfg.data?.token !== token) return new Response("Not found", { status: 404 });

  const { data: todos } = await sb.from("meta").select("data").eq("id", "todos").maybeSingle();
  // deno-lint-ignore no-explicit-any
  const items = ((todos?.data?.items ?? []) as any[]).filter((t) => !t.done && t.due);

  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+/, "");
  const events = items.map((t) =>
    [
      "BEGIN:VEVENT",
      `UID:${t.id}@service-billing-tool`,
      `DTSTAMP:${stamp}`,
      `DTSTART;VALUE=DATE:${ymd(t.due)}`,
      `DTEND;VALUE=DATE:${nextDay(t.due)}`,
      `SUMMARY:${esc((t.pri ? "! " : "") + t.title)}`,
      "TRANSP:TRANSPARENT",
      "BEGIN:VALARM",
      "ACTION:DISPLAY",
      `DESCRIPTION:${esc(t.title)}`,
      "TRIGGER:PT9H",
      "END:VALARM",
      "END:VEVENT",
    ].join("\r\n")
  );

  const ics = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Service Billing Tool//Tasks//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:Billing Tasks",
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
    "X-PUBLISHED-TTL:PT1H",
    ...events,
    "END:VCALENDAR",
  ].join("\r\n");

  return new Response(ics, {
    headers: { "Content-Type": "text/calendar; charset=utf-8", "Cache-Control": "no-cache" },
  });
});
