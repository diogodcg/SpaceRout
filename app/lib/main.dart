import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/supabase_config.dart';
import 'core/ui/theme/app_theme.dart';
import 'core/ui/tokens/app_typography.dart';
import 'features/assinatura/data/assinatura_config.dart';
import 'features/assinatura/data/assinatura_providers.dart';
import 'features/assinatura/presentation/assinatura_screen.dart';
import 'features/auth/data/auth_providers.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/convites/presentation/convites_screen.dart';
import 'features/home/presentation/home_astronauta_screen.dart';
import 'features/home/presentation/home_responsavel_screen.dart';
import 'features/loja/presentation/loja_astronauta_screen.dart';
import 'features/loja/presentation/meus_pedidos_screen.dart';
import 'features/loja/presentation/premios_screen.dart';
import 'features/loja/presentation/resgates_screen.dart';
import 'features/missoes/presentation/comprovacoes_screen.dart';
import 'features/missoes/presentation/missoes_astronauta_screen.dart';
import 'features/missoes/presentation/missoes_screen.dart';
import 'features/notificacoes/data/notificacoes_providers.dart';
import 'features/organizacao/data/organizacao_providers.dart';
import 'features/organizacao/presentation/onboarding_screen.dart';
import 'features/relatorio/presentation/relatorio_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  // Push notifications (FCM) só tem suporte Android por enquanto — iOS
  // precisa de APNs Authentication Key, que só é gerável com Apple
  // Developer Program pago (mesmo bloqueio do Sign in with Apple). Sem
  // esse guard, Firebase.initializeApp() falharia em runtime no iOS por
  // não ter GoogleService-Info.plist configurado no Xcode.
  if (Platform.isAndroid) {
    await Firebase.initializeApp();
    // Assinatura (RevenueCat) — mesmo bloqueio de plataforma que o resto
    // do app paga/push: iOS fica pra quando o Apple Developer Program
    // pago existir. `configure` só identifica o SDK; associar a
    // organização (Purchases.logIn) acontece em vincularAssinaturaProvider,
    // depois do login.
    await Purchases.configure(PurchasesConfiguration(AssinaturaConfig.revenueCatApiKey));
  }
  runApp(const ProviderScope(child: SpaceRoutApp()));
}

class SpaceRoutApp extends StatelessWidget {
  const SpaceRoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpaceRout',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.spaceRoutTheme,
      home: const _AuthGate(),
    );
  }
}

/// Decide entre login, onboarding e app autenticado com base na sessão do
/// Supabase e na existência de linha em `usuarios` (PLANO_MIGRACAO.md §5.3).
/// Convite aceito automaticamente por trigger já deixa a linha pronta; sem
/// convite, cai no onboarding para criar a organização.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    final isSignedIn = authState.maybeWhen(
      data: (state) => state.session != null,
      orElse: () => Supabase.instance.client.auth.currentSession != null,
    );

    if (!isSignedIn) return const LoginScreen();

    final usuarioAtual = ref.watch(usuarioAtualProvider);
    return usuarioAtual.when(
      data: (usuario) {
        if (usuario == null) return const OnboardingScreen();
        ref.watch(registrarNotificacoesProvider);
        ref.watch(vincularAssinaturaProvider(usuario['organizacao_id'] as String));
        return usuario['role'] == 'responsavel'
            ? const _DrawerShell(
                headerTitulo: 'Comando da Missão',
                itens: _painelResponsavelItens,
              )
            : const _DrawerShell(
                headerTitulo: 'Painel de Voo',
                itens: _painelAstronautaItens,
              );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('Erro: $error'))),
    );
  }
}

class _PainelItem {
  const _PainelItem(this.titulo, this.icone, this.tela);

  final String titulo;
  final IconData icone;
  final Widget tela;
}

/// Cadastro de missões, aprovação de comprovações ("Status das Missões"),
/// cadastro de prêmios ("Suprimentos") e confirmação de resgates ("Pedidos
/// do Astronauta") — ver descrição do domínio em PLANO_MIGRACAO.md §5.5 /
/// README.md.
const _painelResponsavelItens = [
  _PainelItem('Início', Icons.home_rounded, HomeResponsavelScreen()),
  _PainelItem('Missões', Icons.rocket_launch, MissoesScreen()),
  _PainelItem('Status das Missões', Icons.fact_check, ComprovacoesScreen()),
  _PainelItem('Suprimentos', Icons.inventory_2, PremiosScreen()),
  _PainelItem('Pedidos do Astronauta', Icons.shopping_bag, ResgatesScreen()),
  _PainelItem('Relatório', Icons.bar_chart, RelatorioScreen()),
  _PainelItem('Convites', Icons.person_add, ConvitesScreen()),
  _PainelItem('Assinatura', Icons.workspace_premium, AssinaturaScreen()),
];

/// Missões em aberto (com envio de comprovação), loja pra resgatar
/// suprimentos e histórico dos próprios pedidos.
const _painelAstronautaItens = [
  _PainelItem('Início', Icons.home_rounded, HomeAstronautaScreen()),
  _PainelItem('Missões', Icons.rocket_launch, MissoesAstronautaScreen()),
  _PainelItem('Suprimentos', Icons.storefront, LojaAstronautaScreen()),
  _PainelItem('Status dos Suprimentos', Icons.shopping_bag, MeusPedidosScreen()),
];

/// Shell genérico com navegação por menu-sanduíche (Drawer) em vez de
/// TabBar — mais legível com rótulos longos e evita o problema de abas
/// cortadas fora da tela.
class _DrawerShell extends ConsumerStatefulWidget {
  const _DrawerShell({required this.headerTitulo, required this.itens});

  final String headerTitulo;
  final List<_PainelItem> itens;

  @override
  ConsumerState<_DrawerShell> createState() => _DrawerShellState();
}

class _DrawerShellState extends ConsumerState<_DrawerShell> {
  int _indice = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itens[_indice].titulo),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        widget.headerTitulo,
                        style: AppTypography.displayHeader.copyWith(fontSize: 20),
                      ),
                    ),
                  ),
                  for (var i = 0; i < widget.itens.length; i++)
                    ListTile(
                      leading: Icon(widget.itens[i].icone),
                      title: Text(widget.itens[i].titulo),
                      selected: i == _indice,
                      onTap: () {
                        setState(() => _indice = i);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Sobre o SpaceRout'),
              onTap: () {
                Navigator.of(context).pop();
                launchUrl(
                  Uri.parse('https://spacerout.com.br'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sair'),
              onTap: () => ref.read(authRepositoryProvider).signOut(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      body: widget.itens[_indice].tela,
    );
  }
}
