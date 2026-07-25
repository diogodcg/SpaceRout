import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/friendly_error.dart';
import '../../../core/ui/components/primary_space_button.dart';
import '../../assinatura/presentation/assinatura_screen.dart';
import '../../organizacao/data/organizacao_providers.dart';
import '../../organizacao/presentation/astronautas_multi_select.dart';
import '../data/missoes_providers.dart';
import '../data/recorrencia_labels.dart';

/// Criação/edição de uma missão (`coordenadas_voo`). Em modo de edição só
/// altera título/moedas/recorrência — status e aprovação ficam em
/// [ComprovacoesScreen].
class MissaoFormScreen extends ConsumerStatefulWidget {
  const MissaoFormScreen({super.key, this.missao});

  final Map<String, dynamic>? missao;

  @override
  ConsumerState<MissaoFormScreen> createState() => _MissaoFormScreenState();
}

class _MissaoFormScreenState extends ConsumerState<MissaoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _tituloController =
      TextEditingController(text: widget.missao?['titulo'] as String?);
  late final _moedasController = TextEditingController(
    text: widget.missao != null ? '${widget.missao!['moedas']}' : '',
  );
  late String _recorrencia = widget.missao?['recorrencia'] as String? ?? 'diaria';
  late Set<String> _astronautas = {
    if (widget.missao?['atribuido_a'] != null) widget.missao!['atribuido_a'] as String,
  };
  bool _loading = false;
  String? _error;
  bool _erroEhLimitePlano = false;

  bool get _editando => widget.missao != null;

  @override
  void dispose() {
    _tituloController.dispose();
    _moedasController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_editando && _astronautas.isEmpty) {
      setState(() {
        _error = 'Selecione um ou mais astronautas.';
        _erroEhLimitePlano = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _erroEhLimitePlano = false;
    });
    try {
      final repo = ref.read(missoesRepositoryProvider);
      final moedas = int.parse(_moedasController.text.trim());
      if (_editando) {
        await repo.atualizarMissao(
          widget.missao!['id'] as String,
          titulo: _tituloController.text.trim(),
          moedas: moedas,
          recorrencia: _recorrencia,
        );
      } else {
        final usuario = ref.read(usuarioAtualProvider).value;
        await repo.criarMissao(
          organizacaoId: usuario!['organizacao_id'] as String,
          titulo: _tituloController.text.trim(),
          moedas: moedas,
          recorrencia: _recorrencia,
          astronautaIds: _astronautas.toList(),
        );
      }
      ref.invalidate(missoesListProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = descreverErro(e);
        _erroEhLimitePlano = ehLimiteDoPlanoGratuito(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar missão' : 'Nova missão')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _tituloController,
                enabled: !_loading,
                decoration: const InputDecoration(labelText: 'Título'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Digite um título.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _moedasController,
                enabled: !_loading,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Moedas'),
                validator: (value) {
                  final n = int.tryParse(value?.trim() ?? '');
                  return (n == null || n <= 0) ? 'Digite um número maior que zero.' : null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _recorrencia,
                decoration: const InputDecoration(labelText: 'Recorrência'),
                items: [
                  for (final entry in recorrenciaLabel.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: _loading
                    ? null
                    : (value) => setState(() => _recorrencia = value!),
              ),
              const SizedBox(height: 16),
              if (_editando)
                // Atribuição não é editável depois de criada — a linha já
                // tem seu próprio ciclo de comprovação, então trocar o
                // astronauta no meio do caminho é ambíguo. Pra reatribuir,
                // excluir e recriar.
                ref.watch(astronautasProvider).when(
                      data: (astronautas) {
                        final nomesPorId = {
                          for (final a in astronautas) a['id'] as String: a['nome_exibicao'] as String,
                        };
                        final nomes = _astronautas.map((id) => nomesPorId[id] ?? '?').join(', ');
                        return Text('Atribuído a: ${nomes.isEmpty ? 'Qualquer um' : nomes}');
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text('Erro ao carregar astronautas: $error'),
                    )
              else
                AstronautasMultiSelect(
                  selecionados: _astronautas,
                  enabled: !_loading,
                  onChanged: (value) => setState(() => _astronautas = value),
                ),
              const SizedBox(height: 24),
              PrimarySpaceButton(
                label: 'Salvar',
                onPressed: _salvar,
                isLoading: _loading,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (_erroEhLimitePlano)
                  TextButton(
                    onPressed: () => AssinaturaScreen.abrir(context),
                    child: const Text('Assinar'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
