// Varre coordenadas_voo em busca de:
//   1) missões "disponivel" cujo notificar_as já passou -> notifica o(s)
//      astronauta(s) atribuído(s) (ou todos da organização, se atribuido_a
//      for null). Repete a cada INTERVALO_LEMBRETE_MS enquanto continuar
//      "disponivel" (lembrete periódico, não só uma vez).
//   2) missões que já receberam o PRIMEIRO lembrete, continuam "disponivel"
//      e passaram do prazo de tolerância -> notifica todos os responsaveis
//      da organização (uma única vez).
//
// Chamada a cada minuto pelo pg_cron (ver migration
// 20260722000000_agendamento_lembretes_missao_pg_cron.sql), autenticada por
// um segredo compartilhado próprio (header x-cron-secret) — não pelas
// chaves anon/service_role da Supabase, que exigiriam verify_jwt=true e não
// funcionam com o novo sistema de API keys (sb_publishable_/sb_secret_).
import { createClient } from "npm:@supabase/supabase-js@2";
import { enviarFcm, horaAtualNoFuso, obterAccessTokenFcm, ServiceAccount } from "../_shared/fcm.ts";

const TOLERANCIA_ESCALONAMENTO_MS = 2 * 60 * 60 * 1000; // 2h, ajustável
const INTERVALO_LEMBRETE_MS = 2 * 60 * 60 * 1000; // 2h entre lembretes periódicos ao astronauta
const FUSO_HORARIO_FAMILIA = "America/Sao_Paulo"; // v1: um único fuso pra
// todas as organizações — não há coluna de timezone por organização no
// schema hoje.

Deno.serve(async (req) => {
  const segredoEsperado = Deno.env.get("CRON_SHARED_SECRET");
  if (!segredoEsperado || req.headers.get("x-cron-secret") !== segredoEsperado) {
    return new Response("unauthorized", { status: 401 });
  }

  const sa: ServiceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")!);
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, // client server-to-server, ignora RLS
  );

  const accessToken = await obterAccessTokenFcm(sa);

  const resumo = { lembretes: 0, escalonamentos: 0, tokensRemovidos: 0, erros: 0 };

  // --- 1) LEMBRETE AO ASTRONAUTA ------------------------------------------
  // UPDATE ... RETURNING atômico: "claim" das linhas antes de enviar, para
  // que duas execuções sobrepostas do cron nunca disparem o mesmo lembrete
  // duas vezes (Postgres reavalia o WHERE por linha sob READ COMMITTED).
  const agora = new Date();
  const horaAtual = horaAtualNoFuso(FUSO_HORARIO_FAMILIA);
  const limiteProximoLembrete = new Date(agora.getTime() - INTERVALO_LEMBRETE_MS).toISOString();

  // Primeiro lembrete do dia: só depois de notificar_as.
  const { data: primeiroLembrete, error: erroPrimeiroLembrete } = await supabase
    .from("coordenadas_voo")
    .update({ primeiro_lembrete_em: agora.toISOString(), lembrete_enviado_em: agora.toISOString() })
    .eq("ativa", true)
    .eq("status", "disponivel")
    .not("notificar_as", "is", null)
    .is("primeiro_lembrete_em", null)
    .lte("notificar_as", horaAtual)
    .select("id, titulo, organizacao_id, atribuido_a");

  if (erroPrimeiroLembrete) {
    console.error("Erro ao buscar/marcar missões para o primeiro lembrete", erroPrimeiroLembrete);
    resumo.erros++;
  }

  // Lembretes periódicos seguintes: já teve o primeiro, continua disponivel,
  // passou o intervalo desde o último lembrete enviado.
  const { data: lembretePeriodico, error: erroLembretePeriodico } = await supabase
    .from("coordenadas_voo")
    .update({ lembrete_enviado_em: agora.toISOString() })
    .eq("ativa", true)
    .eq("status", "disponivel")
    .not("primeiro_lembrete_em", "is", null)
    .lte("lembrete_enviado_em", limiteProximoLembrete)
    .select("id, titulo, organizacao_id, atribuido_a");

  if (erroLembretePeriodico) {
    console.error("Erro ao buscar/marcar missões para lembrete periódico", erroLembretePeriodico);
    resumo.erros++;
  }

  const missoesLembrete = [...(primeiroLembrete ?? []), ...(lembretePeriodico ?? [])];

  for (const missao of missoesLembrete) {
    let usuarioIds: string[];
    if (missao.atribuido_a) {
      usuarioIds = [missao.atribuido_a];
    } else {
      // Missão aberta: lembrete vai para todos os astronautas da organização.
      const { data: astronautas } = await supabase
        .from("usuarios")
        .select("id")
        .eq("organizacao_id", missao.organizacao_id)
        .eq("role", "astronauta");
      usuarioIds = (astronautas ?? []).map((u) => u.id);
    }
    if (usuarioIds.length === 0) continue;

    const { data: dispositivos } = await supabase
      .from("dispositivos_notificacao")
      .select("id, fcm_token")
      .in("usuario_id", usuarioIds);

    for (const disp of dispositivos ?? []) {
      const resultado = await enviarFcm(
        accessToken,
        sa.project_id,
        disp.fcm_token,
        "Missão te espera!",
        `Não esqueça: "${missao.titulo}"`,
        { tipo: "lembrete_missao", missao_id: missao.id },
      );
      if (resultado.ok) {
        resumo.lembretes++;
      } else {
        resumo.erros++;
        if (resultado.tokenInvalido) {
          await supabase.from("dispositivos_notificacao").delete().eq("id", disp.id);
          resumo.tokensRemovidos++;
        }
      }
    }
  }

  // --- 2) ESCALONAMENTO AO(S) RESPONSÁVEL(IS) -----------------------------
  // Medido a partir do PRIMEIRO lembrete (não do último periódico), para não
  // adiar o aviso ao responsável só porque o lembrete periódico ao
  // astronauta continua repetindo.
  const limiteEscalonamento = new Date(Date.now() - TOLERANCIA_ESCALONAMENTO_MS).toISOString();
  const { data: missoesEscalonamento, error: erroEscalonamento } = await supabase
    .from("coordenadas_voo")
    .update({ escalonado_em: new Date().toISOString() })
    .eq("ativa", true)
    .eq("status", "disponivel")
    .not("notificar_as", "is", null)
    .not("primeiro_lembrete_em", "is", null)
    .is("escalonado_em", null)
    .lte("primeiro_lembrete_em", limiteEscalonamento)
    .select("id, titulo, organizacao_id");

  if (erroEscalonamento) {
    console.error("Erro ao buscar/marcar missões para escalonamento", erroEscalonamento);
    resumo.erros++;
  }

  for (const missao of missoesEscalonamento ?? []) {
    // Múltiplos responsáveis por organização (fluxo de convite) — todos
    // recebem, não só quem criou a missão.
    const { data: responsaveis } = await supabase
      .from("usuarios")
      .select("id")
      .eq("organizacao_id", missao.organizacao_id)
      .eq("role", "responsavel");
    const usuarioIds = (responsaveis ?? []).map((u) => u.id);
    if (usuarioIds.length === 0) continue;

    const { data: dispositivos } = await supabase
      .from("dispositivos_notificacao")
      .select("id, fcm_token")
      .in("usuario_id", usuarioIds);

    for (const disp of dispositivos ?? []) {
      const resultado = await enviarFcm(
        accessToken,
        sa.project_id,
        disp.fcm_token,
        "Missão pendente",
        `"${missao.titulo}" ainda não foi cumprida.`,
        { tipo: "escalonamento_missao", missao_id: missao.id },
      );
      if (resultado.ok) {
        resumo.escalonamentos++;
      } else {
        resumo.erros++;
        if (resultado.tokenInvalido) {
          await supabase.from("dispositivos_notificacao").delete().eq("id", disp.id);
          resumo.tokensRemovidos++;
        }
      }
    }
  }

  console.log("enviar-lembretes-missao concluído", resumo);
  return new Response(JSON.stringify(resumo), {
    headers: { "Content-Type": "application/json" },
  });
});
