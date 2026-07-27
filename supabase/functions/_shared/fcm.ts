// Helpers compartilhados de autenticação/envio via FCM HTTP v1 API, usados
// por enviar-lembretes-missao e reiniciar_missoes_recorrentes.
import { importPKCS8, SignJWT } from "npm:jose@5";

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri: string;
  project_id: string;
}

export function horaAtualNoFuso(timeZone: string): string {
  const partes = new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).formatToParts(new Date());
  const pega = (tipo: string) => partes.find((p) => p.type === tipo)?.value ?? "00";
  return `${pega("hour")}:${pega("minute")}:${pega("second")}`;
}

export async function obterAccessTokenFcm(sa: ServiceAccount): Promise<string> {
  const chavePrivada = await importPKCS8(sa.private_key, "RS256");
  const agora = Math.floor(Date.now() / 1000);

  const jwt = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience(sa.token_uri)
    .setIssuedAt(agora)
    .setExpirationTime(agora + 3600)
    .sign(chavePrivada);

  const resp = await fetch(sa.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!resp.ok) {
    throw new Error(`Falha ao trocar JWT por access token: ${resp.status} ${await resp.text()}`);
  }
  const dados = await resp.json();
  return dados.access_token as string;
}

export interface ResultadoEnvio {
  ok: boolean;
  tokenInvalido: boolean;
}

export async function enviarFcm(
  accessToken: string,
  projectId: string,
  fcmToken: string,
  titulo: string,
  corpo: string,
  data: Record<string, string>,
): Promise<ResultadoEnvio> {
  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json; charset=UTF-8",
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title: titulo, body: corpo },
          data,
          android: { priority: "high" },
        },
      }),
    },
  );

  if (resp.ok) return { ok: true, tokenInvalido: false };

  const payload = await resp.json().catch(() => null);
  // Formato de erro da FCM HTTP v1 API:
  // { error: { code, message, status, details: [{ "@type": ".../FcmError", errorCode }] } }
  const errorCode = payload?.error?.details?.find((d: Record<string, unknown>) =>
    typeof d["@type"] === "string" && (d["@type"] as string).includes("FcmError")
  )?.errorCode;
  const tokenInvalido = errorCode === "UNREGISTERED" || errorCode === "NOT_FOUND" ||
    errorCode === "INVALID_ARGUMENT";

  console.error("Falha ao enviar FCM", { status: resp.status, errorCode, payload });
  return { ok: false, tokenInvalido };
}
