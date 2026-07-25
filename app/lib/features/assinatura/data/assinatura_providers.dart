import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'assinatura_repository.dart';

final assinaturaRepositoryProvider = Provider<AssinaturaRepository>((ref) {
  return AssinaturaRepository();
});

/// Chama `Purchases.logIn(organizacaoId)` assim que a organização é
/// conhecida. Observado (`ref.watch`) pelo `_AuthGate`, mesmo padrão de
/// `registrarNotificacoesProvider` — só que aqui a chave é o
/// `organizacao_id`, não o `usuario_id` (assinatura é por família).
final vincularAssinaturaProvider = FutureProvider.family.autoDispose<void, String>((
  ref,
  organizacaoId,
) async {
  if (!Platform.isAndroid) return;
  await ref.read(assinaturaRepositoryProvider).identificarOrganizacao(organizacaoId);
});

/// Ofertas disponíveis pro paywall — vazio até existir uma Offering
/// configurada no RevenueCat (bloqueado até a conexão com o Google Play,
/// ver README.md "Em aberto").
final ofertasAssinaturaProvider = FutureProvider.autoDispose<Offerings>((ref) {
  return ref.watch(assinaturaRepositoryProvider).buscarOfertas();
});
