import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'organizacao_repository.dart';

final organizacaoRepositoryProvider = Provider<OrganizacaoRepository>((ref) {
  return OrganizacaoRepository(Supabase.instance.client);
});

/// Null enquanto o usuário logado não tem linha em `usuarios` — sinal para
/// o `_AuthGate` mostrar o onboarding em vez do app autenticado.
final usuarioAtualProvider = FutureProvider<Map<String, dynamic>?>((ref) {
  return ref.watch(organizacaoRepositoryProvider).buscarUsuarioAtual();
});

final astronautasProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(organizacaoRepositoryProvider).listarAstronautas();
});

/// Plano/tier atual da família — usado na tela de assinatura.
final organizacaoAtualProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) {
  return ref.watch(organizacaoRepositoryProvider).buscarOrganizacaoAtual();
});

/// Total de usuários da família — usado pra recomendar o tier certo.
final totalUsuariosProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(organizacaoRepositoryProvider).contarUsuarios();
});
