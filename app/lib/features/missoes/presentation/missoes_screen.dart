import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/confirm_delete.dart';
import '../../../core/friendly_error.dart';
import '../../../core/ui/components/empty_state.dart';
import '../../../core/ui/components/mission_card.dart';
import '../../assinatura/presentation/assinatura_screen.dart';
import '../../organizacao/data/organizacao_providers.dart';
import '../data/missoes_providers.dart';
import '../data/recorrencia_labels.dart';
import 'missao_form_screen.dart';

class MissoesScreen extends ConsumerWidget {
  const MissoesScreen({super.key});

  Future<void> _excluir(BuildContext context, WidgetRef ref, Map<String, dynamic> missao) async {
    final confirmado = await confirmarExclusao(
      context,
      mensagem: 'Excluir a missão "${missao['titulo']}"? Essa ação não pode ser desfeita.',
    );
    if (!confirmado) return;
    await ref.read(missoesRepositoryProvider).excluirMissao(missao['id'] as String);
    ref.invalidate(missoesListProvider);
  }

  Future<void> _definirAtiva(
    BuildContext context,
    WidgetRef ref,
    String id,
    bool value,
  ) async {
    try {
      await ref.read(missoesRepositoryProvider).definirAtiva(id, value);
      ref.invalidate(missoesListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(descreverErro(e)),
            action: ehLimiteDoPlanoGratuito(e)
                ? SnackBarAction(label: 'Assinar', onPressed: () => AssinaturaScreen.abrir(context))
                : null,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missoes = ref.watch(missoesListProvider);
    final astronautas = ref.watch(astronautasProvider).value ?? const [];
    final nomesPorId = {
      for (final a in astronautas) a['id'] as String: a['nome_exibicao'] as String,
    };

    return Scaffold(
      body: missoes.when(
        data: (lista) {
          if (lista.isEmpty) {
            return const EmptyState(
              title: 'Tudo tranquilo por aqui',
              message: 'Nenhuma missão cadastrada ainda. Crie uma pra começar.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(missoesListProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: lista.length,
              itemBuilder: (context, index) {
                final missao = lista[index];
                final ativa = missao['ativa'] as bool;
                final atribuido = nomesPorId[missao['atribuido_a']] ?? 'Qualquer um';
                return MissionCard(
                  title: missao['titulo'] as String,
                  description:
                      '${recorrenciaLabel[missao['recorrencia']]} · Atribuída a: $atribuido',
                  coins: missao['moedas'] as int,
                  status: missao['status'] as String,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MissaoFormScreen(missao: missao)),
                  ),
                  actions: [
                    Switch(
                      value: ativa,
                      onChanged: (value) =>
                          _definirAtiva(context, ref, missao['id'] as String, value),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MissaoFormScreen(missao: missao),
                        ),
                      ),
                    ),
                    // Só oferece exclusão para missões ainda não usadas —
                    // RLS só permite DELETE com status = 'disponivel' (ver
                    // migration 20260719220000), então mostrar o botão fora
                    // disso resultaria num toque sem efeito nenhum.
                    if (missao['status'] == 'disponivel')
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _excluir(context, ref, missao),
                      ),
                  ],
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erro: $error')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MissaoFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}
