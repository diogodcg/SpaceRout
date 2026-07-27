import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/components/coin_badge.dart';
import '../../../core/ui/components/empty_state.dart';
import '../data/relatorio_providers.dart';

class RelatorioScreen extends ConsumerWidget {
  const RelatorioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relatorio = ref.watch(relatorioAstronautasProvider);

    return Scaffold(
      body: relatorio.when(
        data: (lista) {
          if (lista.isEmpty) {
            return const EmptyState(
              title: 'Nenhum astronauta a bordo',
              message: 'Convide uma criança pra acompanhar o progresso dela por aqui.',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(relatorioAstronautasProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: lista.length,
              itemBuilder: (context, index) {
                final astronauta = lista[index];
                final expiradas = astronauta['missoes_expiradas'] as int? ?? 0;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              astronauta['nome_exibicao'] as String,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            CoinBadge(coins: astronauta['saldo_moedas'] as int),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${astronauta['missoes_concluidas']} missões concluídas · '
                          '${astronauta['missoes_em_aberto']} em aberto'
                          '${expiradas > 0 ? ' · $expiradas perdidas' : ''}',
                        ),
                        Text('${astronauta['premios_conquistados']} prêmios conquistados'),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erro: $error')),
      ),
    );
  }
}
