// Reinicia missões recorrentes (diaria/semanal) uma vez por dia:
//   1) ciclos "disponivel" que passaram do corte do dia sem serem cumpridos
//      -> status='expirada' (não fica em rollover indefinido).
//   2) ciclos concluídos (aprovada/rejeitada) que passaram do corte
//      -> arquivados (ativa=false).
// Em ambos os casos, cria o próximo ciclo (nova linha, disponivel/ativa=true)
// e notifica o(s) astronauta(s) atribuído(s) que tem uma missão nova no dia.
//
// Cada mission definition tem no máximo UMA linha com ativa=true por vez —
// é o que a trava freemium (verificar_limite_freemium) conta. Por isso as
// linhas antigas são arquivadas (ativa=false) ANTES de qualquer linha nova
// ser inserida: pra uma organização que nunca passou do limite atual, o
// total de ativa=true nunca muda por causa deste job. Uma organização com
// dados antigos de antes do limite apertar (mais itens ativos do que o
// limite permite hoje) pode ainda assim esbarrar na trava no MEIO do lote,
// já que o total só volta ao normal no fim — ver o tratamento de erro no
// passo 3 abaixo, que tenta reverter e, se a própria reversão também
// esbarrar na trava (o caso realista pra esse cenário), pelo menos loga
// claramente em vez de falhar em silêncio.
//
// Chamada 1x/dia pelo pg_cron (ver migration
// 20260727000002_agendamento_reiniciar_missoes_pg_cron.sql), mesma
// autenticação por segredo compartilhado (x-cron-secret) de
// enviar-lembretes-missao.
import { createClient } from "npm:@supabase/supabase-js@2";
import { enviarFcm, obterAccessTokenFcm, ServiceAccount } from "../_shared/fcm.ts";

const FUSO_HORARIO_FAMILIA = "America/Sao_Paulo"; // v1: fuso único, sem horário
// de verão (Brasil aboliu em 2019) — meia-noite local é sempre 03:00 UTC.

function inicioDoDiaEmSaoPaulo(): Date {
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: FUSO_HORARIO_FAMILIA,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const pega = (tipo: string) => partes.find((p) => p.type === tipo)?.value ?? "01";
  return new Date(`${pega("year")}-${pega("month")}-${pega("day")}T00:00:00-03:00`);
}

interface CicloParaReiniciar {
  id: string;
  organizacao_id: string;
  titulo: string;
  moedas: number;
  recorrencia: string;
  criado_por: string;
  atribuido_a: string | null;
  notificar_as: string | null;
  // true = veio do passo 1 (estava "disponivel", virou "expirada"); false =
  // veio do passo 2 (estava "aprovada"/"rejeitada", só ativa mudou). Usado
  // pra reverter o arquivamento corretamente se a criação do próximo ciclo
  // falhar (ver comentário no passo 3).
  eraDisponivel: boolean;
}

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

  const resumo = { expiradas: 0, recicladas: 0, notificacoes: 0, tokensRemovidos: 0, erros: 0 };

  const corteDiaria = inicioDoDiaEmSaoPaulo();
  const corteSemanal = new Date(corteDiaria.getTime() - 6 * 24 * 60 * 60 * 1000);
  const filtroCorte = `and(recorrencia.eq.diaria,created_at.lt.${corteDiaria.toISOString()}),` +
    `and(recorrencia.eq.semanal,created_at.lt.${corteSemanal.toISOString()})`;

  const colunasCiclo =
    "id, organizacao_id, titulo, moedas, recorrencia, criado_por, atribuido_a, notificar_as";

  // --- 1) EXPIRA CICLOS NÃO CUMPRIDOS -------------------------------------
  const { data: expiradas, error: erroExpiradas } = await supabase
    .from("coordenadas_voo")
    .update({ status: "expirada", ativa: false })
    .eq("ativa", true)
    .eq("status", "disponivel")
    .neq("recorrencia", "pontual")
    .or(filtroCorte)
    .select(colunasCiclo);

  if (erroExpiradas) {
    console.error("Erro ao expirar ciclos não cumpridos", erroExpiradas);
    resumo.erros++;
  }
  resumo.expiradas = expiradas?.length ?? 0;

  // --- 2) ARQUIVA CICLOS CONCLUÍDOS ---------------------------------------
  const { data: concluidas, error: erroConcluidas } = await supabase
    .from("coordenadas_voo")
    .update({ ativa: false })
    .eq("ativa", true)
    .in("status", ["aprovada", "rejeitada"])
    .neq("recorrencia", "pontual")
    .or(filtroCorte)
    .select(colunasCiclo);

  if (erroConcluidas) {
    console.error("Erro ao arquivar ciclos concluídos", erroConcluidas);
    resumo.erros++;
  }

  // --- 3) CRIA O PRÓXIMO CICLO + NOTIFICA ---------------------------------
  // Uma organização com mais itens ativos do que o limite freemium atual
  // permite (ex.: dados antigos de antes do limite apertar) pode ter mais de
  // uma missão pra reciclar no mesmo dia — arquivar todas primeiro e só
  // depois inserir, uma a uma, pode fazer uma inserção no meio do lote
  // esbarrar na própria trava freemium da organização (verificar_limite_freemium),
  // já que o total "ativa=true" só volta ao normal no FINAL do lote, não
  // entre cada inserção. Se isso acontecer, reverte o arquivamento da linha
  // antiga em vez de deixar a recorrência desaparecer silenciosamente — ela
  // tenta reciclar de novo no próximo dia.
  const ciclosParaReiniciar: CicloParaReiniciar[] = [
    ...(expiradas ?? []).map((c) => ({ ...c, eraDisponivel: true })),
    ...(concluidas ?? []).map((c) => ({ ...c, eraDisponivel: false })),
  ];

  for (const ciclo of ciclosParaReiniciar) {
    const { data: novoCiclo, error: erroInsercao } = await supabase
      .from("coordenadas_voo")
      .insert({
        organizacao_id: ciclo.organizacao_id,
        titulo: ciclo.titulo,
        moedas: ciclo.moedas,
        recorrencia: ciclo.recorrencia,
        criado_por: ciclo.criado_por,
        atribuido_a: ciclo.atribuido_a,
        notificar_as: ciclo.notificar_as,
      })
      .select("id")
      .single();

    if (erroInsercao) {
      console.error("Erro ao criar próximo ciclo, tentando reverter arquivamento", {
        ciclo: ciclo.id,
        erroInsercao,
      });
      resumo.erros++;
      // Se a falha foi transitória, o revert (ativa=true) recupera a missão
      // normalmente. Mas se a organização já tinha mais itens ativos do que
      // o limite atual permite (dado antigo, de antes do limite apertar), o
      // próprio revert esbarra na mesma trava freemium — não tem como
      // "voltar" sem violar o limite de novo. Nesse caso a missão fica
      // arquivada (não reciclou hoje) e precisa de intervenção manual; loga
      // bem alto pra não passar batido.
      const { error: erroRevert } = await supabase
        .from("coordenadas_voo")
        .update(ciclo.eraDisponivel ? { status: "disponivel", ativa: true } : { ativa: true })
        .eq("id", ciclo.id);
      if (erroRevert) {
        console.error(
          "Revert também falhou — organização provavelmente já estava acima do limite " +
            "freemium atual antes deste job rodar. Missão ficou arquivada sem reciclar; " +
            "precisa de intervenção manual.",
          { ciclo: ciclo.id, organizacao_id: ciclo.organizacao_id, erroRevert },
        );
      }
      continue;
    }
    resumo.recicladas++;

    let usuarioIds: string[];
    if (ciclo.atribuido_a) {
      usuarioIds = [ciclo.atribuido_a];
    } else {
      const { data: astronautas } = await supabase
        .from("usuarios")
        .select("id")
        .eq("organizacao_id", ciclo.organizacao_id)
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
        "Novo dia, nova missão!",
        `Sua missão de hoje: "${ciclo.titulo}"`,
        { tipo: "nova_missao_dia", missao_id: novoCiclo.id },
      );
      if (resultado.ok) {
        resumo.notificacoes++;
      } else {
        resumo.erros++;
        if (resultado.tokenInvalido) {
          await supabase.from("dispositivos_notificacao").delete().eq("id", disp.id);
          resumo.tokensRemovidos++;
        }
      }
    }
  }

  console.log("reiniciar_missoes_recorrentes concluído", resumo);
  return new Response(JSON.stringify(resumo), {
    headers: { "Content-Type": "application/json" },
  });
});
