import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_specs.dart';
import '../tokens/app_typography.dart';
import 'coin_badge.dart';

/// Card de uma linha de `coordenadas_voo` (missão).
///
/// O status é reforçado por cor **e** ícone/rótulo, não só cor: `aprovada`
/// (verde) e `rejeitada` (vermelho) são a dupla clássica que fica
/// indistinguível pra quem tem deuteranopia/protanopia (~8% dos homens).
class MissionCard extends StatelessWidget {
  const MissionCard({
    super.key,
    required this.title,
    required this.description,
    required this.coins,
    required this.status,
    this.onTap,
    this.actions,
  });

  final String title;
  final String description;
  final int coins;
  final String status; // 'disponivel' | 'enviada' | 'aprovada' | 'rejeitada' | 'expirada'
  final VoidCallback? onTap;

  /// Controles específicos da tela (ex.: switch ativa/inativa + editar +
  /// excluir no painel do responsável, ou "Enviar prova" no do astronauta) —
  /// renderizados como um rodapé, separados por divisor.
  final List<Widget>? actions;

  ({Color color, IconData icon, String label}) get _statusVisual {
    switch (status) {
      case 'enviada':
        return (
          color: AppColors.nebulaLilac,
          icon: Icons.hourglass_top_rounded,
          label: 'Aguardando aprovação',
        );
      case 'aprovada':
        return (
          color: AppColors.auroraGreen,
          icon: Icons.check_circle_rounded,
          label: 'Aprovada',
        );
      case 'rejeitada':
        return (
          color: AppColors.superNovaRed,
          icon: Icons.cancel_rounded,
          label: 'Rejeitada',
        );
      case 'expirada':
        return (
          color: AppColors.textSecondary,
          icon: Icons.timer_off_rounded,
          label: 'Perdida',
        );
      default:
        return (
          color: AppColors.surfaceBorder,
          icon: Icons.radio_button_unchecked_rounded,
          label: 'Disponível',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visual = _statusVisual;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpecs.spaceM),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppSpecs.radiusM),
        border: Border.all(color: visual.color, width: 1.5),
        boxShadow: AppSpecs.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpecs.radiusM),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpecs.radiusM),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpecs.spaceM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppTypography.cardTitle),
                          const SizedBox(height: AppSpecs.spaceXS),
                          Text(description, style: AppTypography.bodyText),
                          const SizedBox(height: AppSpecs.spaceS),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(visual.icon, size: 16, color: visual.color),
                              const SizedBox(width: AppSpecs.spaceXS),
                              Text(
                                visual.label,
                                style: AppTypography.bodyText.copyWith(
                                  color: visual.color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpecs.spaceM),
                    CoinBadge(coins: coins),
                  ],
                ),
                if (actions != null) ...[
                  const SizedBox(height: AppSpecs.spaceS),
                  Divider(height: 1, color: AppColors.surfaceBorder),
                  const SizedBox(height: AppSpecs.spaceXS),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: actions!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
