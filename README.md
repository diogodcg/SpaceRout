# SpaceRout

App de gamificação de tarefas domésticas para famílias: responsáveis cadastram
missões e prêmios, crianças ("astronautas") cumprem missões, ganham moedas e
trocam por prêmios. Nasceu como protótipo em Streamlit/Google Sheets
(congelado em [`SpaceRout-Streamlit`](https://github.com/diogodcg/SpaceRout),
pasta irmã deste repo) e está sendo reconstruído aqui como produto real:
apps nativos iOS/Android em Flutter, backend em Supabase.

> Decisões de arquitetura e o raciocínio por trás delas (o "porquê") estão em
> [`PLANO_MIGRACAO.md`](./PLANO_MIGRACAO.md). Este README é só o mapa de
> **onde estamos** — atualize o checklist abaixo a cada etapa concluída.

## Stack

| Camada | Escolha |
|---|---|
| Banco + backend | Supabase (Postgres + Auth + RLS + Storage) |
| Frontend mobile | Flutter (`app/`), Riverpod, `supabase_flutter` |
| Push notifications | Firebase Cloud Messaging |
| Assinatura | RevenueCat (IAP App Store / Play Store) |

Projeto Supabase: `SpaceRout` (ref `kzizdekhohisnixyzlqj`). CLI local já
linkado — `supabase db push` aplica migrations pendentes direto.

## Portais externos

| Portal | Pra que serve | Link |
|---|---|---|
| Supabase Dashboard | Banco/Auth/RLS/Storage/Edge Functions/Vault (segredos) do projeto `SpaceRout` | [dashboard](https://supabase.com/dashboard/project/kzizdekhohisnixyzlqj) |
| Resend | Envio dos e-mails de convite (API + verificação de domínio, hoje pendente) | [resend.com/domains](https://resend.com/domains) |
| Google Cloud Console | Client IDs OAuth (Web/Android/iOS) do login com Google | [console.cloud.google.com/apis/credentials](https://console.cloud.google.com/apis/credentials) |
| Firebase Console | Projeto FCM (push notifications), `google-services.json`/`GoogleService-Info.plist`, service account | [console.firebase.google.com](https://console.firebase.google.com/) |
| Apple Developer | Capability "Sign in with Apple", APNs Authentication Key (push iOS) — precisa de conta paga | [developer.apple.com/account](https://developer.apple.com/account) |
| RevenueCat | Assinatura/IAP (App Store e Play Store) — ainda não integrado | [app.revenuecat.com](https://app.revenuecat.com/) |

## Estado atual

### ✅ Feito

- **Estrutura de pastas Flutter** feature-first (`app/lib/core/`,
  `app/lib/features/{auth,organizacao,missoes,loja,notificacoes}/`), ver
  `PLANO_MIGRACAO.md` §5.4 — pastas de features ainda vazias, aguardando
  telas/login social
- **Schema do banco** (`supabase/migrations/`), todas aplicadas no projeto remoto:
  - `organizacoes_familiares`, `usuarios`, `coordenadas_voo` (missões),
    `suprimentos_cosmicos` (loja), RLS completo, trava freemium (5 itens
    ativos no plano gratuito)
  - `resgates_suprimentos` (histórico de resgate com débito atômico de
    saldo), RPC `enviar_comprovacao_missao`
  - Onboarding (RPC `criar_organizacao`), convites completos com aceite
    automático no primeiro login, `unique` em `usuarios.email`, correção de
    RLS (astronauta não atualiza `coordenadas_voo` direto), colunas de
    notificação (`notificar_as` etc.) + tabela `dispositivos_notificacao`,
    bucket privado `comprovacoes` no Storage
- **Esqueleto Flutter** (`app/`): projeto criado, `supabase_flutter` +
  `flutter_riverpod` instalados, `main.dart` inicializa o client e mostra
  tela de conexão OK
- **Código de login social** (`app/lib/features/auth/`): `AuthRepository`
  com `signInWithGoogle`/`signInWithApple` (troca idToken por sessão do
  Supabase via `signInWithIdToken`), `LoginScreen`, e `main.dart` já roteia
  entre login e app autenticado conforme a sessão. `flutter analyze` limpo.
- **Login com Google testado e funcionando ponta a ponta** (simulador iOS):
  clients Web/Android/iOS criados no Google Cloud Console, `webClientId` em
  `app/lib/core/google_auth_config.dart`, `GIDClientID` +
  `REVERSED_CLIENT_ID` no `Info.plist` (iOS), SHA-1 de debug registrado
  (Android), provider Google habilitado no Supabase Dashboard com os Client
  IDs Web *e* iOS na lista (o idToken do iOS usa o client iOS como
  audience, não o Web). `AuthRepository` gera um nonce próprio (hash
  SHA-256 pro Google em `initialize()`, valor cru pro
  `signInWithIdToken()`) — o Supabase rejeita o token se o nonce não
  bater. Sessão autenticada confirmada com conta real.
- **Onboarding de organização nova** (`app/lib/features/organizacao/`):
  `OrganizacaoRepository` busca a linha do usuário em `usuarios` e chama a
  RPC `criar_organizacao`; `OnboardingScreen` pede o nome da família.
  `_AuthGate` (`main.dart`) agora decide entre login → onboarding → app
  autenticado, checando se o usuário logado já tem linha em `usuarios`.
  Testado ponta a ponta no simulador iOS: login sem organização cai na tela
  de onboarding, criar a família ("Família Teste") navega pra home. `flutter
  analyze` limpo.
- **Painel do responsável** — cadastro de missões/prêmios, aprovação de
  comprovações e confirmação de resgates:
  - `app/lib/features/missoes/`: `MissoesRepository`/providers (CRUD de
    `coordenadas_voo` — criar, editar, ativar/desativar) e
    `listarComprovacoesPendentes`/`validarComprovacao` (fila de
    `status = 'enviada'`, aprovar credita moedas via trigger existente,
    rejeitar não). `MissoesScreen`, `MissaoFormScreen`, `ComprovacoesScreen`
    (foto via signed URL do bucket privado `comprovacoes`).
  - `app/lib/features/loja/`: `LojaRepository`/providers (CRUD de
    `suprimentos_cosmicos`) e `confirmarEntrega` (fila de resgates
    `status = 'solicitado'` → `'entregue'`). `PremiosScreen`,
    `PremioFormScreen`, `ResgatesScreen`.
  - **Exclusão** (botão "X", com diálogo de confirmação em
    `core/confirm_delete.dart`), distinta do toggle ativa/inativa: dá pro
    responsável tanto pausar temporariamente uma missão/suprimento quanto
    excluir de vez o que não serve mais. Missão só pode ser excluída com
    `status = 'disponivel'` (RLS nova, migration
    `20260719220000_exclusao_missoes_disponiveis` — uma missão já
    enviada/aprovada não pode ser apagada pra não perder a trilha de moedas
    já creditadas); suprimento com resgate vinculado é bloqueado pela FK
    `on delete restrict` já existente. Testado no simulador iOS: exclusão de
    missão e de suprimento confirmadas funcionando.
  - `_AuthGate` (`main.dart`) agora roteia por `usuario['role']`: responsável
    cai num shell "Comando da Missão" navegado por **menu-sanduíche
    (Drawer)** — trocado de `TabBar` por feedback de usabilidade (rótulos
    longos como "Pedidos do Astronauta" cortavam fora da tela numa TabBar
    scrollável). AppBar mostra a seção atual como título; Drawer lista as 4
    seções com ícone temático cada (Missões/Status das Missões/Suprimentos/
    Pedidos do Astronauta — só os rótulos visíveis mudaram, classes/tabelas
    continuam Comprovações/Prêmios/Resgates internamente); astronauta
    continua no placeholder (painel dele é o próximo passo).
  - Testado ponta a ponta no simulador iOS: cadastro de missão e de
    suprimento confirmados funcionando (CRUD completo, toggle ativo/inativa).
    Fila de "Status das Missões"/"Pedidos do Astronauta" usa o mesmo padrão
    já validado, mas ainda não tem dados reais pra exercitar (depende do
    painel do astronauta enviar comprovação/resgatar suprimento). `flutter
    analyze` limpo.
- **Painel do astronauta** (`app/lib/features/missoes/.../missoes_astronauta_screen.dart`,
  `app/lib/features/loja/.../loja_astronauta_screen.dart` +
  `meus_pedidos_screen.dart`): lista de missões em aberto (atribuídas a ele
  ou abertas pra qualquer um) com envio de comprovação (`image_picker`,
  câmera/galeria — permissões `NSCameraUsageDescription`/
  `NSPhotoLibraryUsageDescription` no `Info.plist`), loja com saldo de
  moedas e resgate (débito atômico via trigger existente), e "Meus Pedidos"
  com status do resgate. Testado ponta a ponta no simulador iOS (alternando
  o `role` da conta de teste via REST API + service role key, já que o app
  só tem login social): cadastro → comprovação com foto → aprovação com
  foto visível (signed URL) → crédito de moedas confirmado (saldo 0 → 4);
  resgate → débito atômico confirmado (saldo 4 → 1) → confirmação de
  entrega pelo responsável. `flutter analyze` limpo.
- **Atribuição de missão/suprimento a um ou mais astronautas** (multi-seleção
  obrigatória, substituiu a versão anterior de seleção única com "Qualquer
  um"): formulários de missão/suprimento trocaram o dropdown por uma lista
  de checkboxes (`AstronautasMultiSelect`, em
  `app/lib/features/organizacao/presentation/`) — é obrigatório marcar pelo
  menos um astronauta pra salvar (`'Selecione um ou mais astronautas.'` se
  nenhum marcado), não existe mais "aberto pra qualquer um" via formulário.
  Marcar mais de um **duplica**: cria uma linha independente por astronauta
  (mesmo título/moedas/recorrência/custo), cada uma com seu próprio ciclo de
  comprovação/aprovação/moedas — **testado e corrigido em duas rodadas**:
  a primeira versão ligava as linhas por um `missao_grupo_id` pra editar
  título/moedas em bloco, mas o teste no simulador mostrou que editar uma
  linha não deve afetar as irmãs (cada astronauta é 100% independente depois
  de criado) — `missao_grupo_id` foi revertido (migration
  `20260721010000_remover_grupo_missao`). Suprimento usa uma tabela de
  junção (`suprimentos_atribuicoes`, migration
  `20260721000000_atribuicao_multipla_astronautas`) no lugar da antiga
  coluna `atribuido_a`, com guard equivalente no trigger
  `processar_resgate_suprimento`. Edição (de missão ou suprimento) não
  mexe em quem está atribuído — só título/moedas/custo/recorrência daquela
  linha; pra reatribuir, excluir e recriar.
- **Tela "Relatório"** (`app/lib/features/relatorio/`): lista cada
  astronauta com saldo de moedas, missões concluídas/em aberto e prêmios já
  conquistados (RPC `relatorio_astronautas`) — substitui o seletor de
  criança que existia antes no Drawer (removido: `criancaSelecionadaProvider`
  e a filtragem das 4 telas do responsável por ele). Como o Drawer do
  responsável ficou idêntico ao do astronauta depois da reversão, os dois
  passaram a usar o mesmo `_DrawerShell` genérico em `main.dart` (a classe
  `_PainelResponsavel` foi removida).
- **Nomenclatura temática do painel do astronauta**: "Painel de Voo" (era
  "SpaceRout" genérico) — ecoa `coordenadas_voo`, contrasta com "Comando da
  Missão" do responsável (ele comanda de fora, a criança pilota de dentro).
  Seções: "Missões" / "Suprimentos" (era "Loja" — alinhado com o nome do
  responsável) / "Status dos Suprimentos" (era "Meus Pedidos" — evita a
  palavra "aprovado", já que resgate não tem etapa de aprovação, só
  confirmação de entrega).
- **Logout movido pro rodapé do Drawer** (nos dois painéis): antes era um
  ícone solto na AppBar, agora é um item "Sair" fixo embaixo da lista de
  seções, separado por divisor — padrão mais comum pra ação de sair.
- **Fluxo de convite** (`app/lib/features/convites/`): tela "Convites" no
  Drawer do responsável (só ele, não aparece no painel do astronauta) —
  criar convite (e-mail + role `responsavel`/`astronauta`),
  listar com status computado no client (`Pendente`/`Aceito`/`Expirado`,
  a partir de `aceito`/`expira_em` — não existe coluna de status no banco),
  reenviar (reseta `expira_em` +7 dias) e excluir. O aceite em si já era
  100% automático desde o schema (trigger `aceitar_convite_no_login` em
  `auth.users`), então não existe nem precisa existir tela de "aceitar
  convite" — a pessoa convidada só loga normalmente e cai direto na
  organização/role certos. Testado ponta a ponta no simulador: convite
  pro e-mail real de um filho, aceite automático confirmado (usuário cai
  direto no painel de astronauta, sem passar por onboarding). `flutter
  analyze` limpo.
- **Push notifications (infra) — escopo Android**: lembrete de missão
  (`notificar_as`) e escalonamento pro responsável (`PLANO_MIGRACAO.md`
  §5.1) implementados ponta a ponta. `app/lib/features/notificacoes/`
  (registro de token FCM em `dispositivos_notificacao`, disparado pelo
  `_AuthGate` assim que há `usuario_id`) + Edge Function
  `supabase/functions/enviar-lembretes-missao` (Deno, assina JWT RS256 da
  service account do Firebase via `npm:jose` pra autenticar contra a FCM
  HTTP v1 API) + `pg_cron` chamando a function a cada minuto (migration
  `20260722000000_agendamento_lembretes_missao_pg_cron.sql`). Autenticação
  `pg_cron → Edge Function` via segredo compartilhado próprio
  (`x-cron-secret`, guardado no Supabase Vault) em vez das chaves
  anon/service_role — o projeto já usa as novas API keys
  (`sb_publishable_/sb_secret_`), que não são JWT e não passam no gate
  `verify_jwt` das Edge Functions. Testado com `curl` direto na function
  (200 OK) e `flutter build apk --debug` (build Android limpo). **iOS
  fica de fora**: enviar push via FCM pro iOS também exige Apple Developer
  Program pago (APNs Authentication Key só é gerável no portal pago) —
  mesmo bloqueio do Sign in with Apple, ver item abaixo.
- **Notificação de convite por e-mail (Resend)**: criar ou reenviar um
  convite agora dispara um e-mail de verdade pro convidado — trigger
  `notificar_convite_por_email` em `convites_familiares` (dispara em
  `INSERT` ou quando `expira_em` muda no reenvio, nunca no `UPDATE` de
  aceite automático) chama `net.http_post` pra Edge Function
  `supabase/functions/enviar-email-convite`, que manda o e-mail via API do
  Resend. Mesmo padrão de autenticação trigger→function do push
  (`x-convite-secret` no Vault). **Sem domínio verificado no Resend, só
  entrega pro próprio e-mail da conta** (remetente padrão
  `onboarding@resend.dev`) — testado enviando pro e-mail do usuário,
  recebido com sucesso; falta verificar um domínio antes de mandar pra
  convidados de verdade. **Sem link de download** no e-mail por enquanto
  (app não publicado) — só a instrução de pedir o app pra quem convidou.
- **Design System "Starlight" v1.0** (`app/lib/core/ui/`): tokens de cor
  (`tokens/app_colors.dart`), geometria/espaçamento/sombra
  (`tokens/app_specs.dart`) e tipografia (`tokens/app_typography.dart` —
  par Space Grotesk pros elementos de "painel de comando"
  (headers/títulos/botões) + Plus Jakarta Sans pro corpo de texto + Space
  Mono no contador de moedas, algarismos de largura fixa); componentes
  `PrimarySpaceButton`, `CoinBadge` e `MissionCard`
  (`components/`); tema global `AppTheme.spaceRoutTheme`
  (`theme/app_theme.dart`) ligado no `MaterialApp` — cobre não só os
  componentes novos mas os widgets Material que as telas já usam
  (`TextFormField`, `Checkbox`, `Drawer`, `AlertDialog`, `SnackBar`), pra
  não ficar metade do app "Starlight" e metade Material default. Dark
  first, cantos arredondados (radius 8/16/24), Calm Technology (sem
  animação exagerada). Ajustes feitos em cima da primeira proposta: 4º
  status (`rejeitada`) no `MissionCard`, reforçado por ícone + rótulo além
  da cor (aprovada/rejeitada em verde/vermelho pastel seriam
  indistinguíveis pra daltonismo só por cor); único momento animado do
  sistema é o "twinkle" (escala + glow) do `CoinBadge` quando o saldo
  sobe — respeita "reduzir movimento" do sistema, resto do app sem
  animação. Testado no simulador iOS (precisou subir
  `IPHONEOS_DEPLOYMENT_TARGET` de 13.0 pra 15.0 no Xcode — exigência do
  Firebase, nunca tinha sido testado no simulador iOS antes).
- **Telas migradas pro Design System "Starlight"**: Missões (responsável
  e astronauta) usam `MissionCard` (status com ícone + rodapé de ações —
  switch/editar/excluir ou "Enviar prova"); Suprimentos, Loja do
  astronauta, Pedidos, Resgates e Relatório trocaram os textos soltos de
  "X moedas" pelo `CoinBadge`; `cardTheme` global cobre os `Card` de
  Comprovações e Relatório sem precisar mexer nesses arquivos. Corrigido
  no processo: `FloatingActionButtonThemeData` (o FAB ficava roxo do
  Material default, fora do tema, só percebido num screenshot real do
  simulador). Testado com dados sintéticos (astronauta + 2 missões + 1
  suprimento criados direto no banco via `supabase db query --linked`,
  depois removidos) — confirmado visualmente no simulador (`MissionCard`
  com borda verde/cinza por status, `CoinBadge` no Relatório), não só
  `flutter analyze` limpo.
- **Mascote "Stellar"** (tag `v0.0.8`): primeira peça de identidade visual
  além dos tokens do Starlight — nasceu de uma exploração com 3 direções
  (cometa/símbolo da moeda, astronauta cadete, drone de missão),
  apresentada num artefato visual com mockups ao vivo antes de
  implementar. `StellarMascot` (`core/ui/components/stellar_mascot.dart`)
  é um `CustomPainter` puro, sem asset de imagem, então nunca borra em
  nenhum tamanho. Substitui o ícone padrão do Flutter (iOS/Android/Web,
  via `flutter_launcher_icons` a partir de `assets/branding/`), o ícone
  genérico do `CoinBadge`, e virou a base de um novo componente
  `EmptyState` (mascote + título + mensagem) que trocou o texto seco de
  "Nenhum X cadastrado ainda" em 8 telas (missões, comprovações,
  convites, relatório, pedidos, resgates, loja) por algo mais acolhedor.
  Estático por design — a única animação do sistema continua sendo o
  "twinkle" do `CoinBadge`, não o mascote em si. Ficou de fora por
  enquanto: ícone monocromático dedicado pra barra de notificação do
  Android (guideline própria da plataforma, precisa de emulador Android
  pra testar, que não tinha disponível na sessão).
- **Auditoria de padrões do Design System "Starlight"** (tag `v0.0.9`):
  catálogo de todos os padrões de nomenclatura/estrutura do projeto
  (pastas por feature, convenção de classes, terminologia por role,
  enums) apresentado num artefato visual antes de qualquer mudança, pra
  decisão informada do usuário sobre o que valia corrigir. Correções
  aplicadas: `PrimarySpaceButton` (existia mas nunca era usado) agora é
  o CTA das 5 telas com botão único de formulário (Salvar
  missão/suprimento, Enviar convite, Criar família, Entrar com
  Google/Apple), com loading embutido no lugar do
  `if (_loading) spinner else FilledButton` repetido em cada tela;
  `elevatedButtonTheme` (morto — o app só usa `FilledButton`, nunca
  `ElevatedButton`) virou `filledButtonTheme` de verdade, cobrindo os
  botões compactos inline (Aprovar, Enviar prova, Confirmar entrega,
  Resgatar); removida a borda manual que sobrescrevia o tema em 4
  formulários; 5 `TextStyle` soltos trocados pelos tokens de
  `AppTypography`; "Loja vazia" → "Suprimentos vazios" (a última string
  visível que ainda usava o nome pré-rename); mapa de rótulo de
  recorrência, duplicado em 3 arquivos com 2 nomes diferentes,
  consolidado em `features/missoes/data/recorrencia_labels.dart`; enum
  `user_role` renomeado pra `role_tipo` (alinha com o padrão `_tipo`/
  `_status` dos outros enums do schema); `PLANO_MIGRACAO.md` corrigido
  pra refletir o schema real de `resgates_suprimentos` (divergia do
  `resgates_cosmicos` cogitado no plano original). Deixado de propósito
  fora do escopo: renomear a tabela `resgates_suprimentos` em si — já é
  referenciada em várias telas/RLS/triggers, risco não compensa o ganho
  cosmético.
- **Tela "Início" (Home)** pros dois roles (tag `v0.0.9`): antes o app
  caía direto em "Missões" sem nenhuma saudação. Novo primeiro item do
  Drawer em `features/home/` — mascote Stellar, saudação com o nome do
  usuário e cartões-resumo (`SummaryTile`,
  `core/ui/components/summary_tile.dart`) reaproveitando providers já
  existentes, sem repositório novo: responsável vê comprovações/pedidos
  aguardando e quantos astronautas tem na família; astronauta vê saldo
  de moedas (`CoinBadge`) e quantas missões estão disponíveis/aguardando
  aprovação. Testado no simulador nos dois roles — pro astronauta, como
  o login é só social e os mocks não têm credencial real, a verificação
  foi feita alternando temporariamente o role da conta real via
  `supabase db query --linked` (mesmo padrão já usado antes pra testar o
  painel do astronauta), revertido logo em seguida.
- **Emulador Android configurado nessa máquina** (2026-07-23): SDK já
  existia (via Android Studio) mas sem `cmdline-tools`/AVD — instalado
  `cmdline-tools` via Homebrew e criado o AVD `SpaceRout_Pixel_Play`
  (Pixel 7, imagem Google Play `android-34`). App testado ponta a ponta
  nele: comportamento idêntico ao iOS em todas as telas. Único ponto
  que precisou de ajuste no ambiente (não no código): o
  `google_sign_in` v7 usa o Credential Manager do Android, que só
  autentica se já existir uma conta Google cadastrada no sistema —
  precisou entrar com uma conta de verdade em Configurações → Contas
  antes do "Entrar com Google" funcionar (a primeira tentativa, com uma
  imagem "Google APIs" sem Play Store, nem chegava a oferecer isso).
- **Mensagem amigável pro limite do plano gratuito** (tag `v0.1.0`):
  ao tentar ativar uma 6ª missão ou suprimento, o trigger
  `verificar_limite_freemium` recusava a operação, mas o app mostrava o
  erro cru do Postgres (`PostgrestException(message: Plano gratuito
  permite no máximo 5 itens ativos em coordenadas_voo, code: 23514...`)
  — achado testando no emulador Android. Novo helper
  `core/friendly_error.dart` (`descreverErro`) reconhece esse erro
  específico (código `23514` + nome da tabela na mensagem) e troca por
  uma frase sem jargão técnico, diferenciando missão de suprimento.
  Aplicado nos 4 lugares que podem disparar o limite: criar/editar
  missão, criar/editar suprimento, e os switches de ativar/desativar
  nas listas — que antes nem tratavam esse erro (falhavam em silêncio,
  sem feedback nenhum pro usuário). Testado no simulador com a
  organização já no limite de 5 itens ativos.
- **Domínio próprio verificado no Resend** (2026-07-23): comprado
  `spacerout.com.br` (Registro.br), registros DNS (DKIM, SPF/MX, DMARC)
  cadastrados e verificados no Resend. `enviar-email-convite/index.ts`
  trocou o remetente de `onboarding@resend.dev` (sandbox, só entregava
  pro próprio e-mail da conta) pra `SpaceRout <contato@spacerout.com.br>`,
  deploy feito. Testado ponta a ponta: convite real criado via
  `supabase db query --linked` pro e-mail do usuário
  (`diogo.dcg@gmail.com`), `net._http_response` confirmou 200 do Resend,
  e-mail chegou certinho na caixa — convite de teste removido depois.
  Texto do e-mail ainda pede pra "quem convidou passar o aplicativo"
  em vez de linkar a loja, porque o app não está publicado ainda —
  decisão de propósito, atualizar quando publicar (ver "Em aberto").
- **Ícone adaptativo do Android** (2026-07-23): o ícone do app na tela
  inicial não tinha configuração de ícone adaptativo (`flutter_launcher_icons`
  só usava `image_path`, um PNG quadrado único) — Android 8+ trata isso
  como "legacy icon" e o resultado varia por launcher. Adicionado
  `adaptive_icon_background`/`adaptive_icon_foreground` no `pubspec.yaml`,
  com um novo asset só da mascote em fundo transparente
  (`assets/branding/stellar_icon_foreground.svg`/`.png`, sem o encolhimento
  manual que cheguei a tentar primeiro — o inset de 16% que o próprio
  `flutter_launcher_icons` aplica já é a margem de segurança recomendada
  pelo Android, encolher os dois juntos deixava a mascote pequena demais).
  Testado no emulador Android: ícone correto e completo (com a
  estrelinha) tanto na gaveta de apps quanto via Configurações → Todos
  os apps. Um "anel amarelo" que apareceu durante os testes na tela
  inicial era só o destaque temporário do launcher pra ícone recém
  adicionado (confirmado vendo o mesmo efeito depois no ícone do Play
  Store) — não era um problema real do nosso ícone.

- **Site institucional publicado** (`docs/`, 2026-07-23): 3 páginas
  estáticas (Sobre, Perguntas frequentes, Privacidade e Termos) no
  mesmo Design System "Starlight" (paleta/tipografia do app), no ar via
  GitHub Pages no domínio próprio `spacerout.com.br` — GitHub Pages
  habilitado (`main` / `docs`), DNS cadastrado no Registro.br (4
  registros A na raiz + CNAME `www`), propagou rápido (bem mais rápido
  que os do Resend) e o site já responde 200 em `http://spacerout.com.br`.
  HTTPS ainda provisionando (automático pelo GitHub, sem ação
  necessária). Resolve a exigência de link de política de privacidade
  da Play Store. A política cobre LGPD com cuidado extra pela parte de
  crianças: base legal por tratamento (art. 7º), consentimento
  específico do responsável pra dados de criança (art. 14),
  encarregado/DPO nomeado (art. 41), lista completa de direitos do
  titular + revogação de consentimento + canal da ANPD (art. 18).
  **Não é validação jurídica** — recomendado revisar com advogado antes
  de publicar de verdade, principalmente a parte de crianças (ver
  "Em aberto").
- **Link "Sobre o SpaceRout" no Drawer** (2026-07-23): usuário notou que o
  menu-sanduíche não linkava pro site institucional recém-publicado.
  Adicionado `url_launcher` (novo plugin nativo — precisou reiniciar o
  `flutter run`, hot reload não basta) e um `ListTile` novo em
  `main.dart`, depois do divisor e antes do "Sair" (mesmo padrão de
  ação, não de navegação interna) — decisão deliberada de não misturar
  com os itens funcionais (Missões, Convites etc.), que são de uso
  frequente; "Sobre" é consulta rara. Abre `https://spacerout.com.br`
  no navegador externo. Presente nos dois Drawers (responsável e
  astronauta), já que ambos usam o mesmo `_DrawerShell`. Testado no
  simulador iOS pelo usuário.
- **Revisão do Drawer sugerida pelo "PO Gemini"** (2026-07-23): usuário
  mostrou a tela do menu pro parceiro de produto, que trouxe 3 pontos.
  2 já estavam cobertos e não precisaram de mudança (conferido no
  código antes de mexer, não só aceito de olho): o `DrawerHeader` do
  próprio Flutter já soma `MediaQuery.paddingOf(context).top` no
  padding — não colide com a Dynamic Island — e o `listTileTheme` em
  `app_theme.dart` já pinta ícone+texto do item ativo de
  `stardustYellow` (dava pra ver isso na própria screenshot). O
  terceiro procedia: faltava `debugShowCheckedModeBanner: false` no
  `MaterialApp` — a faixa vermelha "DEBUG" aparecia em todo screenshot
  do simulador. Adicionado e confirmado visualmente.
- **`contato@spacerout.com.br` recebendo e-mail** (2026-07-24): domínio
  já estava com nameservers no Cloudflare desde a verificação do Resend
  (confirmado via `dig NS`, nada a mexer no Registro.br). Configurado
  **Cloudflare Email Routing**: ativado o serviço (cria MX
  `route1/2/3.mx.cloudflare.net` + TXT SPF/DKIM na raiz do domínio —
  não colide com o MX do Resend, que fica em `send.spacerout.com.br`,
  subdomínio separado), endereço de destino verificado (caixa pessoal
  do usuário, separada do Gmail de propósito) e regra de roteamento
  `contato@spacerout.com.br` → esse destino. Levou alguns minutos pra
  propagar depois de ativado — teste com e-mail real confirmou entrega.
- **Modelo de dados do freemium com tiers pagos** (2026-07-25,
  `supabase/migrations/20260725000000_modelo_freemium_tiers_pagos.sql`,
  aplicado no remoto via `supabase db push --linked`): trigger
  `verificar_limite_freemium` apertado de 5 pra 3 itens ativos; coluna
  nova `organizacoes_familiares.plano_max_usuarios` (NULL enquanto
  gratuito — nesse plano não há teto de gente, só de itens); trigger
  novo `verificar_limite_usuarios_convite` que barra criar convite além
  do teto do plano pago. Decisão de design: a trava de tamanho de
  família fica na **criação do convite**, não num trigger na tabela
  `usuarios` — a linha de `usuarios` é criada dentro de
  `aceitar_convite_no_login`, que roda como trigger `AFTER INSERT` em
  `auth.users`; uma exceção ali quebraria a transação de login/cadastro
  do Supabase Auth pro convidado em vez de mostrar um aviso amigável pra
  quem está convidando. `friendly_error.dart` corrigido (as mensagens de
  missão/suprimento ainda citavam o limite antigo de 5) e ganhou a
  mensagem do novo erro de limite de usuários. **Falta**: integração
  RevenueCat, que é quem vai popular `plano`/`plano_max_usuarios` de
  verdade quando alguém assinar (ver "Em aberto").
- **Webhook do RevenueCat** (2026-07-25, `supabase/functions/webhook-revenuecat/`,
  deployado): recebe eventos de assinatura (compra, renovação, upgrade/
  downgrade de tier, expiração) e atualiza
  `organizacoes_familiares.plano`/`plano_max_usuarios`. Autenticado por
  segredo compartilhado no header `Authorization` (`REVENUECAT_WEBHOOK_SECRET`,
  mesmo padrão de `x-convite-secret`/`x-cron-secret`). Pressupõe que o
  app chama `Purchases.logIn(organizacaoId)` antes do paywall — é assim
  que `event.app_user_id` chega já sendo o id da organização, sem
  precisar de tabela de mapeamento. `CANCELLATION` isolado não derruba o
  plano (assinatura continua válida até expirar de verdade); só
  `EXPIRATION` volta pra `gratuito`. Testado ponta a ponta via `curl`
  (401 sem auth, 200 no evento `TEST` do painel, compra sintética
  virando `plano='anual'`/`plano_max_usuarios=7`, expiração voltando pro
  gratuito) contra uma organização sintética, removida depois. Product
  IDs esperados no Google Play/App Store/RevenueCat (nomes exatos, ou o
  mapeamento no código precisa mudar): `spacerout_familia_anual` (Tier
  1, 4 usuários) e `spacerout_familia_grande_anual` (Tier 2, 7
  usuários). **Falta**: criar conta no RevenueCat, cadastrar esses dois
  produtos (Play Console + RevenueCat), configurar o webhook no painel
  do RevenueCat apontando pra
  `https://kzizdekhohisnixyzlqj.supabase.co/functions/v1/webhook-revenuecat`
  com o segredo (guardado só no Supabase Vault, não neste arquivo) no
  campo "Authorization Header", e integrar o SDK `purchases_flutter` no
  app (paywall, `Purchases.logIn`, tela de gerenciar assinatura) — nada
  disso feito ainda.
- **SDK `purchases_flutter` + tela "Assinatura"** (2026-07-25,
  `app/lib/features/assinatura/`): `Purchases.configure` em `main.dart`
  (mesmo ponto de `Firebase.initializeApp`, Android só, mesmo bloqueio de
  sempre) usando a chave de **Test configuration** do RevenueCat
  (`AssinaturaConfig.revenueCatApiKey` — simula compras em sandbox sem
  depender do Play Console, enquanto a conta PJ não sai). Novo
  `vincularAssinaturaProvider` chama `Purchases.logIn(organizacaoId)`
  assim que a organização é conhecida (mesmo padrão de
  `registrarNotificacoesProvider`, ligado no `_AuthGate`). Nova tela
  **Assinatura** no Drawer do responsável: mostra o plano atual (lê
  `organizacoes_familiares.plano`/`plano_max_usuarios` via novo
  `organizacaoAtualProvider`) e lista as ofertas do RevenueCat com botão
  de compra/restaurar, usando `descreverErro` pro mesmo padrão de erro
  amigável das outras telas. Testado ponta a ponta no emulador Android:
  login real disparou o `logIn` e o app_user_id bateu exatamente com o
  `organizacao_id` do usuário no banco (conferido via `supabase db
  query`); a tela renderizou corretamente tanto o estado vazio (sem
  produtos reais ainda) quanto, depois de descoberto que o RevenueCat já
  tinha um produto de exemplo do próprio onboarding deles ("Yearly",
  Test Store), o fluxo de compra completo — RevenueCat mostrou o dialog
  nativo de simulação, a compra foi confirmada, e como o product_id
  ("yearly") não é nenhum dos nossos, o webhook (se chegou a ser
  chamado) teria retornado 422 sem tocar no banco — confirmado que
  `organizacoes_familiares.plano` continuou `gratuito` depois. **Falta**:
  trocar a chave de teste pela Public API Key de verdade e os produtos
  reais assim que o Play Console estiver conectado (ver item acima).
- **Gatilho de upgrade no limite gratuito + recomendação automática de
  tier** (2026-07-25): usuário perguntou por que criar uma tela em vez
  de vender "direto pelo Google Play" — esclarecido que o Play Billing
  não tem loja própria, é sempre o app quem inicia a compra chamando o
  SDK, então a tela é o único jeito de existir um botão "Assinar". A
  partir disso, dois pedidos do usuário: (1) mostrar esse botão no
  próprio erro de limite, não só escondido no menu; (2) recomendar
  automaticamente o tier certo pelo tamanho da família, "pra ficar mais
  simples". Implementado: `ehLimiteDoPlanoGratuito` (novo, em
  `friendly_error.dart`) identifica os 3 erros de trava de plano
  (missão/suprimento/convite); todo `SnackBar`/erro inline que já usava
  `descreverErro` ganhou um botão **Assinar** condicional que abre
  `AssinaturaScreen.abrir(context)` — rota independente com AppBar
  própria, já que a tela original não tem Scaffold (é pensada pra virar
  item do Drawer). Corrigido de passagem: `convite_form_screen.dart`
  usava `e.toString()` cru em vez de `descreverErro` — o erro do
  trigger novo de limite de usuários apareceria com jargão técnico de
  banco se não fosse corrigido agora. Para a recomendação de tier: novo
  `totalUsuariosProvider` conta `usuarios` da organização (RLS já filtra
  por organização, não precisou de filtro explícito); a tela de
  assinatura esconde ofertas que não cobrem o tamanho atual da família
  e marca a mais barata que cobre como "RECOMENDADO PRA SUA FAMÍLIA" —
  produto sem entrada em `AssinaturaConfig.maxUsuariosPorProduto` (como
  o "Yearly" de exemplo) fica sempre visível, sem recomendação, pra não
  desaparecer testes/produtos ainda não mapeados. Testado ponta a ponta
  no emulador: como a organização real já tinha 5 missões ativas de
  antes do limite apertar pra 3, bastou tentar reativar uma pra bater
  na trava de verdade — o snackbar "O plano gratuito permite no máximo 3
  missões ativas..." apareceu com o botão Assinar, que abriu a tela
  corretamente com seta de voltar. A parte de recomendação por tier só
  vai ser visível de verdade quando os produtos reais existirem (ver
  item acima) — a lógica está escrita e comentada, mas o teste visual
  do badge fica pendente até lá.

### 🚧 Em aberto

- [ ] **Lançar no Google Play essa semana** (meta confirmada em
      2026-07-23): Android primeiro por custo (taxa única de USD 25 vs.
      USD 99/ano da Apple). Falta:
  - [x] Conta de desenvolvedor Google Play — taxa paga (2026-07-24),
        cadastro/verificação em andamento, aguardando aprovação da
        documentação pelo Google
  - [ ] Ficha da loja (descrição, ícones, screenshots do app)
  - [ ] Build de release assinado (`flutter build appbundle`, keystore)
  - [ ] Estratégia freemium — modelo, schema, webhook e SDK no app
        prontos e testados em sandbox (ver "Feito" acima). Falta, tudo
        bloqueado até a conta de desenvolvedor Google Play virar PJ (ver
        item abaixo): conectar o Play Console ao app no RevenueCat
        (service account), cadastrar os produtos
        `spacerout_familia_anual` (Tier 1, R$89,90/ano) e
        `spacerout_familia_grande_anual` (Tier 2, R$149,90/ano), e
        trocar a chave de Test configuration pela Public API Key real
        em `AssinaturaConfig`
  - [ ] Os itens abaixo (revisar dados de teste, ícone de notificação,
        revisão jurídica) antes de submeter de verdade
- [ ] **Requisitos novos de conta pessoal no Google Play** (descoberto
      2026-07-24, muda o plano de lançamento desta semana): contas
      pessoais criadas depois de 13/nov/2023 (a nossa) exigem, antes de
      liberar produção: (1) **teste fechado com 12 testadores** (número
      caiu de 20 pra 12 em dez/2024) com opt-in **contínuo por 14 dias
      corridos** — sair e voltar zera a contagem da pessoa; e (2)
      **verificação de identidade num Android físico real** (Android
      10+, sem root, via app do Play Console — emulador não serve).
      Conta de **Organização** parece ficar isenta das duas exigências,
      mas essa rota exige D-U-N-S number (até 30 dias) — pior prazo que
      os 14 dias do teste fechado. Decisão: seguir como pessoa física,
      já que 14 dias é mais rápido; falta confirmar se o usuário tem um
      Android físico à mão e reunir os 12 testadores pra começar a
      contagem o quanto antes.
- [ ] **Revisão jurídica da política de privacidade**: o texto em
      `docs/privacidade.html` foi escrito com cuidado (cobre LGPD art.
      7º/14/18/41), mas não é validação jurídica formal. Recomendado
      revisar com advogado antes de publicar nas lojas, especialmente
      pela parte de consentimento parental de crianças.
- [ ] **Consentimento parental de crianças (produto, não só texto)**: hoje
      o login é sempre social (Google/Apple), inclusive pro astronauta —
      não existe uma etapa separada de consentimento parental explícito
      no fluxo de convite/onboarding além do responsável digitar o e-mail
      da criança. Vale decidir com calma se isso precisa de um passo a
      mais no fluxo antes de publicar de verdade.

- [ ] **Atualizar texto do e-mail de convite com link da loja**: hoje
      (`supabase/functions/enviar-email-convite/index.ts`) pede pra
      "quem convidou passar o aplicativo" porque o app ainda não está
      publicado. Assim que sair a ficha na Play Store, trocar esse
      trecho por um link direto de download.
- [ ] **Ícone de notificação monocromático (Android)**: a barra de status
      do Android hoje herda o ícone colorido do app (`Stellar`), mas a
      guideline do Material Design pede um ícone dedicado, só silhueta
      branca. Ainda não feito, mas o motivo antigo (falta de emulador
      Android) não existe mais — emulador `SpaceRout_Pixel_Play`
      configurado em 2026-07-23 (Google Play, ver checkpoint abaixo),
      dá pra validar visualmente quando for fazer.
- [ ] **Antes de publicar**: revisar/apagar organizações e convites de
      teste usados durante o desenvolvimento (ex.: organização atual
      "Cau Gomes - Teste") — inclui os 2 astronautas mock (2026-07-22,
      com missões/suprimentos/resgate sintéticos) criados pra demo
      manual do projeto, deixados de propósito até essa etapa
- [ ] **Sign in with Apple**: adiado — precisa de conta paga no Apple
      Developer Program, que o usuário ainda não tem. O botão de Apple já
      existe na `LoginScreen` (só aparece em iOS/macOS) mas vai dar erro se
      tocado antes da capability estar configurada. Retomar quando a conta
      sair:
  - [ ] Apple Developer: habilitar capability "Sign in with Apple" no App ID
        e no projeto Xcode (Signing & Capabilities), gera o entitlements
        automaticamente
  - [ ] Supabase Dashboard → Authentication → Providers: habilitar Apple,
        colando o Client ID/Service ID criado
  - [ ] Antes de submeter à App Store: obrigatório por regra da Apple
        sempre que Google Sign-In é oferecido em iOS (ver
        PLANO_MIGRACAO.md §5) — não bloqueia desenvolvimento, só submissão
- [ ] **Push notifications no iOS**: bloqueado pelo mesmo motivo do Sign in
      with Apple (Apple Developer Program pago, precisa da APNs
      Authentication Key). `GoogleService-Info.plist` já baixado, guardado
      pra quando desbloquear — só falta configurar no Xcode + subir a APNs
      key no Firebase Console + tirar o guard `Platform.isAndroid` de
      `main.dart`/`notificacoes_providers.dart`
- [ ] **Telas** — portar do protótipo, uma feature por vez:
  - [x] Auth / onboarding de organização nova
  - [x] Painel do responsável (cadastro de missões e prêmios, aprovação de
        comprovação, confirmação de resgate)
  - [x] Painel do astronauta (lista de missões, envio de comprovação, loja,
        resgate)
  - [x] Fluxo de convite (responsável convida, aceite automático no login)
- [ ] **Assinatura**: integração RevenueCat + Edge Function que atualiza
      `organizacoes_familiares.plano`/`plano_expira_em`

## Estrutura do repo

```
spacerout/
  PLANO_MIGRACAO.md   # decisões de arquitetura e o porquê de cada uma
  supabase/
    config.toml        # config de Edge Functions (ex.: verify_jwt)
    migrations/        # schema, aplicado via `supabase db push`
    functions/
      enviar-lembretes-missao/  # lembrete/escalonamento de missão via FCM (pg_cron)
      enviar-email-convite/     # e-mail de convite via Resend (trigger)
  app/                 # projeto Flutter
    lib/
      core/            # client Supabase, config
        ui/            # Design System "Starlight" (tokens, componentes, tema)
      features/
        auth/          # login social (Google/Apple)
        home/          # tela "Início" (boas-vindas + resumo) por role
        organizacao/   # onboarding de organização nova, multi-select de astronautas
        missoes/       # cadastro de missões + aprovação de comprovações
        loja/          # cadastro de prêmios + confirmação de resgates
        relatorio/     # saldo/missões/prêmios por astronauta
        convites/      # convidar responsável/astronauta pra família
        notificacoes/  # registro de token FCM (push, Android)
      main.dart        # _AuthGate: login → onboarding → painel por role
```
