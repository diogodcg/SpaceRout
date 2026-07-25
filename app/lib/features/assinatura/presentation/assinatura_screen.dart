import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/friendly_error.dart';
import '../../../core/ui/components/empty_state.dart';
import '../../../core/ui/components/primary_space_button.dart';
import '../../../core/ui/tokens/app_specs.dart';
import '../../../core/ui/tokens/app_typography.dart';
import '../../organizacao/data/organizacao_providers.dart';
import '../data/assinatura_config.dart';
import '../data/assinatura_providers.dart';

/// Status do plano atual + lista de ofertas pra assinar/trocar de tier.
/// Só aparece no menu do responsável — é quem decide o plano da família.
///
/// Usada de dois jeitos: como item do `_DrawerShell` (sem Scaffold
/// próprio, a AppBar/Drawer é compartilhada) e, via [abrir], empurrada
/// como rota independente com sua própria AppBar — é o atalho "Assinar"
/// mostrado quando o limite do plano gratuito é atingido em outra tela.
class AssinaturaScreen extends ConsumerStatefulWidget {
  const AssinaturaScreen({super.key});

  static void abrir(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Assinatura')),
          body: const AssinaturaScreen(),
        ),
      ),
    );
  }

  @override
  ConsumerState<AssinaturaScreen> createState() => _AssinaturaScreenState();
}

class _AssinaturaScreenState extends ConsumerState<AssinaturaScreen> {
  String? _comprandoPacote;
  bool _restaurando = false;

  Future<void> _comprar(Package pacote) async {
    setState(() => _comprandoPacote = pacote.identifier);
    try {
      await ref.read(assinaturaRepositoryProvider).comprar(pacote);
      ref.invalidate(organizacaoAtualProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Compra confirmada! Pode levar alguns instantes pro plano atualizar aqui.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(descreverErro(e))));
      }
    } finally {
      if (mounted) setState(() => _comprandoPacote = null);
    }
  }

  Future<void> _restaurar() async {
    setState(() => _restaurando = true);
    try {
      await ref.read(assinaturaRepositoryProvider).restaurar();
      ref.invalidate(organizacaoAtualProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Compras restauradas.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(descreverErro(e))));
      }
    } finally {
      if (mounted) setState(() => _restaurando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final organizacao = ref.watch(organizacaoAtualProvider);
    final ofertas = ref.watch(ofertasAssinaturaProvider);
    final totalUsuarios = ref.watch(totalUsuariosProvider).value;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpecs.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          organizacao.when(
            data: (org) => _StatusPlano(
              plano: org?['plano'] as String? ?? 'gratuito',
              maxUsuarios: org?['plano_max_usuarios'] as int?,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(descreverErro(e)),
          ),
          const SizedBox(height: AppSpecs.spaceXL),
          Text('Planos disponíveis', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpecs.spaceM),
          ofertas.when(
            data: (offerings) {
              final todosPacotes = offerings.current?.availablePackages ?? const [];
              if (todosPacotes.isEmpty) {
                return const EmptyState(
                  title: 'Nenhum plano disponível ainda',
                  message:
                      'Estamos preparando os planos pagos. Volte em breve pra conhecer as '
                      'opções.',
                );
              }

              // Esconde planos que não cobrem o tamanho atual da família —
              // não faz sentido oferecer o Tier 1 (4 usuários) pra quem já
              // tem 6. Produto sem entrada em maxUsuariosPorProduto (ainda
              // não cadastrado, ou o "yearly" de exemplo do RevenueCat) fica
              // sempre visível, sem recomendação. `.split(':').first` cobre
              // o formato "productId:basePlanId" que o Android usa.
              int? maxDoPacote(Package p) => AssinaturaConfig
                  .maxUsuariosPorProduto[p.storeProduct.identifier.split(':').first];

              final pacotes = totalUsuarios == null
                  ? todosPacotes
                  : todosPacotes.where((p) {
                      final max = maxDoPacote(p);
                      return max == null || totalUsuarios <= max;
                    }).toList();

              if (pacotes.isEmpty) {
                return EmptyState(
                  title: 'Nenhum plano cobre sua família ainda',
                  message:
                      'Sua família tem $totalUsuarios pessoas — ainda não temos um plano '
                      'pra esse tamanho. Fale com a gente em contato@spacerout.com.br.',
                );
              }

              String? recomendadoId;
              if (totalUsuarios != null) {
                final comMax = pacotes.where((p) => maxDoPacote(p) != null).toList()
                  ..sort((a, b) => maxDoPacote(a)!.compareTo(maxDoPacote(b)!));
                if (comMax.isNotEmpty) recomendadoId = comMax.first.identifier;
              }

              return Column(
                children: [
                  for (final pacote in pacotes) ...[
                    _OfertaCard(
                      pacote: pacote,
                      comprando: _comprandoPacote == pacote.identifier,
                      recomendado: pacote.identifier == recomendadoId,
                      onComprar: () => _comprar(pacote),
                    ),
                    const SizedBox(height: AppSpecs.spaceM),
                  ],
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(descreverErro(e)),
          ),
          const SizedBox(height: AppSpecs.spaceL),
          Center(
            child: TextButton(
              onPressed: _restaurando ? null : _restaurar,
              child: Text(_restaurando ? 'Restaurando...' : 'Já assinei — restaurar compras'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPlano extends StatelessWidget {
  const _StatusPlano({required this.plano, required this.maxUsuarios});

  final String plano;
  final int? maxUsuarios;

  @override
  Widget build(BuildContext context) {
    final descricao = plano == 'anual' && maxUsuarios != null
        ? 'Plano anual — até $maxUsuarios usuários na família'
        : 'Plano gratuito — até 3 missões e 3 suprimentos ativos';

    return Container(
      padding: const EdgeInsets.all(AppSpecs.spaceM),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpecs.radiusM),
      ),
      child: Row(
        children: [
          Icon(
            plano == 'anual' ? Icons.workspace_premium : Icons.rocket_launch_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: AppSpecs.spaceM),
          Expanded(child: Text(descricao, style: AppTypography.bodyText)),
        ],
      ),
    );
  }
}

class _OfertaCard extends StatelessWidget {
  const _OfertaCard({
    required this.pacote,
    required this.comprando,
    required this.recomendado,
    required this.onComprar,
  });

  final Package pacote;
  final bool comprando;
  final bool recomendado;
  final VoidCallback onComprar;

  @override
  Widget build(BuildContext context) {
    final produto = pacote.storeProduct;
    return Container(
      padding: const EdgeInsets.all(AppSpecs.spaceM),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpecs.radiusM),
        border: recomendado
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recomendado) ...[
            Text(
              'RECOMENDADO PRA SUA FAMÍLIA',
              style: AppTypography.bodyText.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpecs.spaceXS),
          ],
          Text(produto.title, style: AppTypography.cardTitle),
          const SizedBox(height: AppSpecs.spaceXS),
          Text(produto.description, style: AppTypography.bodyText),
          const SizedBox(height: AppSpecs.spaceS),
          Text(
            produto.priceString,
            style: AppTypography.cardTitle.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: AppSpecs.spaceM),
          PrimarySpaceButton(
            label: 'Assinar',
            isLoading: comprando,
            onPressed: onComprar,
          ),
        ],
      ),
    );
  }
}
