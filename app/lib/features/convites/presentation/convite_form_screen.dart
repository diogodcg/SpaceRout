import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/friendly_error.dart';
import '../../../core/ui/components/primary_space_button.dart';
import '../../assinatura/presentation/assinatura_screen.dart';
import '../../organizacao/data/organizacao_providers.dart';
import '../data/convites_providers.dart';

const _roles = {
  'astronauta': 'Astronauta (criança)',
  'responsavel': 'Responsável',
};

/// Criação de convite (`convites_familiares`). Sem edição — o único campo
/// que muda depois de criado é a expiração, reenviada direto na lista
/// (ver [ConvitesScreen]).
class ConviteFormScreen extends ConsumerStatefulWidget {
  const ConviteFormScreen({super.key});

  @override
  ConsumerState<ConviteFormScreen> createState() => _ConviteFormScreenState();
}

class _ConviteFormScreenState extends ConsumerState<ConviteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String _role = 'astronauta';
  bool _loading = false;
  String? _error;
  bool _erroEhLimitePlano = false;
  bool _consentimentoLgpd = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == 'astronauta' && !_consentimentoLgpd) {
      setState(() => _error = 'Confirme o consentimento antes de enviar o convite.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _erroEhLimitePlano = false;
    });
    try {
      final usuario = ref.read(usuarioAtualProvider).value;
      await ref.read(convitesRepositoryProvider).criarConvite(
            organizacaoId: usuario!['organizacao_id'] as String,
            email: _emailController.text.trim(),
            role: _role,
            consentimentoLgpd: _consentimentoLgpd,
          );
      ref.invalidate(convitesListProvider);
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
      appBar: AppBar(title: const Text('Novo convite')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail convidado'),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return email.contains('@') ? null : 'Digite um e-mail válido.';
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Convidar como'),
                items: [
                  for (final entry in _roles.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                ],
                onChanged: _loading
                    ? null
                    : (value) => setState(() {
                          _role = value!;
                          if (_role != 'astronauta') _consentimentoLgpd = false;
                        }),
              ),
              if (_role == 'astronauta') ...[
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: _consentimentoLgpd,
                  onChanged: _loading ? null : (value) => setState(() => _consentimentoLgpd = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Confirmo que sou responsável legal por esta criança/adolescente e '
                    'autorizo o tratamento dos dados dela, conforme a Política de '
                    'Privacidade (art. 14 da LGPD).',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              PrimarySpaceButton(
                label: 'Enviar convite',
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
