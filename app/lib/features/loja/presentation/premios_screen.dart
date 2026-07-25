import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/confirm_delete.dart';
import '../../../core/friendly_error.dart';
import '../../../core/ui/components/coin_badge.dart';
import '../../../core/ui/components/empty_state.dart';
import '../../assinatura/presentation/assinatura_screen.dart';
import '../../organizacao/data/organizacao_providers.dart';
import '../data/loja_providers.dart';
import 'premio_form_screen.dart';

class PremiosScreen extends ConsumerWidget {
  const PremiosScreen({super.key});

  Future<void> _excluir(BuildContext context, WidgetRef ref, Map<String, dynamic> premio) async {
    final confirmado = await confirmarExclusao(
      context,
      mensagem: 'Excluir o suprimento "${premio['nome']}"? Essa ação não pode ser desfeita.',
    );
    if (!confirmado) return;
    try {
      await ref.read(lojaRepositoryProvider).excluirPremio(premio['id'] as String);
      ref.invalidate(premiosListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível excluir: já tem resgate vinculado a esse suprimento.')),
        );
      }
    }
  }

  Future<void> _definirAtivo(
    BuildContext context,
    WidgetRef ref,
    String id,
    bool value,
  ) async {
    try {
      await ref.read(lojaRepositoryProvider).definirAtivo(id, value);
      ref.invalidate(premiosListProvider);
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
    final premios = ref.watch(premiosListProvider);
    final astronautas = ref.watch(astronautasProvider).value ?? const [];
    final nomesPorId = {
      for (final a in astronautas) a['id'] as String: a['nome_exibicao'] as String,
    };

    return Scaffold(
      body: premios.when(
        data: (lista) {
          if (lista.isEmpty) {
            return const EmptyState(
              title: 'Suprimentos vazios',
              message: 'Cadastre um suprimento pra criança poder trocar moedas por ele.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(premiosListProvider.future),
            child: ListView.builder(
              itemCount: lista.length,
              itemBuilder: (context, index) {
                final premio = lista[index];
                final ativo = premio['ativo'] as bool;
                final atribuicoes = (premio['suprimentos_atribuicoes'] as List)
                    .cast<Map<String, dynamic>>();
                final nomes = atribuicoes
                    .map((a) => nomesPorId[a['astronauta_id']] ?? '?')
                    .join(', ');
                final atribuido = nomes.isEmpty ? 'Qualquer um' : nomes;
                return ListTile(
                  title: Text(premio['nome'] as String),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        CoinBadge(coins: premio['custo_moedas'] as int),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Atribuído a: $atribuido')),
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: ativo,
                        onChanged: (value) =>
                            _definirAtivo(context, ref, premio['id'] as String, value),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PremioFormScreen(premio: premio),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _excluir(context, ref, premio),
                      ),
                    ],
                  ),
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
          MaterialPageRoute(builder: (_) => const PremioFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}
