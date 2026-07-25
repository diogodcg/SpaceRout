// Recebe eventos de assinatura do RevenueCat (compra, renovação,
// cancelamento, expiração) e atualiza organizacoes_familiares.plano /
// plano_max_usuarios. Autenticado pelo header Authorization com um
// segredo compartilhado (REVENUECAT_WEBHOOK_SECRET), configurado no
// campo "Authorization Header" do painel do RevenueCat — mesmo padrão
// de x-convite-secret / x-cron-secret nas outras functions.
//
// Pressupõe que o app Flutter chama Purchases.logIn(organizacaoId) antes
// de mostrar o paywall — é assim que event.app_user_id chega aqui já
// sendo o id da organização, sem precisar de tabela de mapeamento.
import { createClient } from "npm:@supabase/supabase-js@2";

// Product IDs a criar no Google Play Console / App Store Connect e no
// RevenueCat, com esses nomes exatos — plano_max_usuarios de cada tier
// decidido em 2026-07-25 (ver README.md).
const PLANO_MAX_USUARIOS: Record<string, number> = {
  spacerout_familia_anual: 4, // Tier 1 — R$89,90/ano
  spacerout_familia_grande_anual: 7, // Tier 2 — R$149,90/ano
};

// Eventos que significam "assinatura ativa agora" — inclui PRODUCT_CHANGE
// (upgrade/downgrade de tier) e UNCANCELLATION (desfez o cancelamento
// antes de expirar).
const EVENTOS_ATIVA = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
]);

// CANCELLATION por si só não derruba o acesso — a assinatura continua
// válida até a data de expiração; só EXPIRATION realmente encerra.
const EVENTOS_EXPIRA = new Set(["EXPIRATION"]);

Deno.serve(async (req) => {
  const segredoEsperado = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  if (!segredoEsperado || req.headers.get("Authorization") !== segredoEsperado) {
    return new Response("unauthorized", { status: 401 });
  }

  const body = await req.json();
  const evento = body?.event;

  if (!evento?.type) {
    return new Response("missing event.type", { status: 400 });
  }

  // Evento de teste disparado manualmente no painel do RevenueCat
  // ("Send Test Event") — só serve pra confirmar que o endpoint responde.
  if (evento.type === "TEST") {
    return new Response("ok (test event)", { status: 200 });
  }

  const organizacaoId = evento.app_user_id as string | undefined;
  if (!organizacaoId) {
    return new Response("missing event.app_user_id", { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  if (EVENTOS_ATIVA.has(evento.type)) {
    const productId = (evento.new_product_id ?? evento.product_id) as string | undefined;
    const maxUsuarios = productId ? PLANO_MAX_USUARIOS[productId] : undefined;

    if (!maxUsuarios) {
      console.error("product_id desconhecido no evento RevenueCat", { productId, evento });
      return new Response("unknown product_id", { status: 422 });
    }

    const { error } = await supabase
      .from("organizacoes_familiares")
      .update({ plano: "anual", plano_max_usuarios: maxUsuarios })
      .eq("id", organizacaoId);

    if (error) {
      console.error("Falha ao ativar plano", { organizacaoId, error });
      return new Response("failed to update organizacao", { status: 500 });
    }

    return new Response("ok", { status: 200 });
  }

  if (EVENTOS_EXPIRA.has(evento.type)) {
    const { error } = await supabase
      .from("organizacoes_familiares")
      .update({ plano: "gratuito", plano_max_usuarios: null })
      .eq("id", organizacaoId);

    if (error) {
      console.error("Falha ao expirar plano", { organizacaoId, error });
      return new Response("failed to update organizacao", { status: 500 });
    }

    return new Response("ok", { status: 200 });
  }

  // Outros tipos (CANCELLATION isolado, BILLING_ISSUE, TRANSFER,
  // SUBSCRIPTION_PAUSED etc.) não mudam plano/plano_max_usuarios agora —
  // só confirma recebimento pra não entrar em retry do RevenueCat.
  return new Response("ok (no-op)", { status: 200 });
});
