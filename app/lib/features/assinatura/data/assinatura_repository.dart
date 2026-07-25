import 'package:purchases_flutter/purchases_flutter.dart';

/// Fina camada sobre o SDK do RevenueCat. `Purchases.configure` já roda em
/// `main.dart` (mesmo ponto de `Firebase.initializeApp`) — este repositório
/// só cobre as ações depois disso: identificar a organização, listar
/// ofertas e comprar/restaurar.
class AssinaturaRepository {
  /// Associa o usuário do RevenueCat ao **id da organização**, não ao
  /// usuário individual — é a família que assina, não a pessoa. É assim
  /// que o webhook (`webhook-revenuecat`) recebe `event.app_user_id` já
  /// sendo o `organizacao_id`, sem precisar de tabela de mapeamento.
  Future<void> identificarOrganizacao(String organizacaoId) {
    return Purchases.logIn(organizacaoId);
  }

  /// Ofertas configuradas no RevenueCat (Product catalog → Offerings).
  /// Vazio até existir pelo menos uma — hoje não existe nenhuma, porque os
  /// produtos dependem da conexão com o Google Play (ver README.md).
  Future<Offerings> buscarOfertas() {
    return Purchases.getOfferings();
  }

  Future<CustomerInfo> comprar(Package pacote) async {
    final resultado = await Purchases.purchase(PurchaseParams.package(pacote));
    return resultado.customerInfo;
  }

  Future<CustomerInfo> restaurar() {
    return Purchases.restorePurchases();
  }
}
