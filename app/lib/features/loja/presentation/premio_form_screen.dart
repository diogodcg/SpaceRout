import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/friendly_error.dart';
import '../../../core/ui/components/primary_space_button.dart';
import '../../assinatura/presentation/assinatura_screen.dart';
import '../../organizacao/data/organizacao_providers.dart';
import '../../organizacao/presentation/astronautas_multi_select.dart';
import '../data/loja_providers.dart';

/// Criação/edição de um prêmio (`suprimentos_cosmicos`).
class PremioFormScreen extends ConsumerStatefulWidget {
  const PremioFormScreen({super.key, this.premio});

  final Map<String, dynamic>? premio;

  @override
  ConsumerState<PremioFormScreen> createState() => _PremioFormScreenState();
}

class _PremioFormScreenState extends ConsumerState<PremioFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nomeController =
      TextEditingController(text: widget.premio?['nome'] as String?);
  late final _custoController = TextEditingController(
    text: widget.premio != null ? '${widget.premio!['custo_moedas']}' : '',
  );
  late Set<String> _astronautas = {
    for (final a in (widget.premio?['suprimentos_atribuicoes'] as List? ?? []))
      a['astronauta_id'] as String,
  };
  bool _loading = false;
  String? _error;
  bool _erroEhLimitePlano = false;

  bool get _editando => widget.premio != null;

  @override
  void dispose() {
    _nomeController.dispose();
    _custoController.dispose();
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
      final repo = ref.read(lojaRepositoryProvider);
      final custo = int.parse(_custoController.text.trim());
      if (_editando) {
        await repo.atualizarPremio(
          widget.premio!['id'] as String,
          nome: _nomeController.text.trim(),
          custoMoedas: custo,
        );
      } else {
        final usuario = ref.read(usuarioAtualProvider).value;
        await repo.criarPremio(
          organizacaoId: usuario!['organizacao_id'] as String,
          nome: _nomeController.text.trim(),
          custoMoedas: custo,
          astronautaIds: _astronautas.toList(),
        );
      }
      ref.invalidate(premiosListProvider);
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
      appBar: AppBar(title: Text(_editando ? 'Editar suprimento' : 'Novo suprimento')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nomeController,
                enabled: !_loading,
                decoration: const InputDecoration(labelText: 'Nome do suprimento'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Digite um nome.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _custoController,
                enabled: !_loading,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Custo em moedas'),
                validator: (value) {
                  final n = int.tryParse(value?.trim() ?? '');
                  return (n == null || n <= 0) ? 'Digite um número maior que zero.' : null;
                },
              ),
              const SizedBox(height: 16),
              if (_editando)
                // Reserva não é editável depois de criada — pra mudar,
                // excluir e recriar (mesma lógica de MissaoFormScreen).
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
