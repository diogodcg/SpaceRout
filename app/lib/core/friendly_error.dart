import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduz erros técnicos conhecidos (ex.: limite do plano gratuito, que o
/// banco recusa via trigger `verificar_limite_freemium`) pra mensagens que
/// fazem sentido pro usuário, sem código/detalhe de banco. Erros não
/// mapeados caem no `toString()` de sempre.
String descreverErro(Object erro) {
  if (erro is PostgrestException && erro.code == '23514') {
    if (erro.message.contains('coordenadas_voo')) {
      return 'O plano gratuito permite no máximo 3 missões ativas ao mesmo '
          'tempo. Desative ou exclua uma antes de ativar esta.';
    }
    if (erro.message.contains('suprimentos_cosmicos')) {
      return 'O plano gratuito permite no máximo 3 suprimentos ativos ao '
          'mesmo tempo. Desative ou exclua um antes de ativar este.';
    }
    if (erro.message.contains('convites_familiares')) {
      return 'Seu plano atual não permite mais usuários nesta família. '
          'Faça upgrade pra convidar mais gente.';
    }
  }
  return erro.toString();
}

/// true quando o erro é uma das travas de plano gratuito (item ou usuário)
/// — usado pra decidir se mostra um atalho "Assinar" junto do aviso.
bool ehLimiteDoPlanoGratuito(Object erro) {
  if (erro is! PostgrestException || erro.code != '23514') return false;
  return erro.message.contains('coordenadas_voo') ||
      erro.message.contains('suprimentos_cosmicos') ||
      erro.message.contains('convites_familiares');
}
