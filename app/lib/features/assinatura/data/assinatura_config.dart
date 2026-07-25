/// Chaves e IDs de produto do RevenueCat — públicos por natureza (igual a
/// `SupabaseConfig.publishableKey`), seguros para embutir no cliente.
///
/// [revenueCatApiKey] hoje é a chave de "Test configuration" (RevenueCat →
/// Apps → SpaceRout (Play Store) → Test configuration), que simula compras
/// em sandbox sem depender de loja conectada — usada enquanto a conta de
/// desenvolvedor Google Play (PJ) não é resolvida (ver README.md "Em
/// aberto"). Trocar pela Public API Key do app assim que o Play Console
/// estiver conectado.
///
/// [produtoTier1]/[produtoTier2] precisam bater exatamente com os IDs
/// esperados pelo webhook (`supabase/functions/webhook-revenuecat/index.ts`)
/// e com os produtos cadastrados no Google Play Console.
class AssinaturaConfig {
  static const revenueCatApiKey = 'test_krYNjSldmEELIoMuBRSglaJlkPA';
  static const produtoTier1 = 'spacerout_familia_anual';
  static const produtoTier2 = 'spacerout_familia_grande_anual';
}
