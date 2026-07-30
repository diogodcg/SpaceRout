import 'package:supabase_flutter/supabase_flutter.dart';

/// Convites de família (`convites_familiares`). O aceite é automático via
/// trigger `aceitar_convite_no_login` em `auth.users` — este repository só
/// cobre a gestão pelo responsável (criar, listar, reenviar, excluir).
class ConvitesRepository {
  ConvitesRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<Map<String, dynamic>>> listarConvites() async {
    final rows = await _supabase
        .from('convites_familiares')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Falha com exceção clara se o e-mail já pertence a outra organização
  /// (trigger `verificar_email_convite_disponivel`) ou já tem convite
  /// pra esse par organização/e-mail (`unique (organizacao_id,
  /// email_convidado)`).
  /// [consentimentoLgpd] é obrigatório quando [role] é `astronauta` — o
  /// banco reforça isso via check constraint
  /// (`consentimento_lgpd_obrigatorio_para_astronauta`), registrando o
  /// consentimento específico do responsável exigido pelo art. 14 da LGPD
  /// pra tratar dados de menor (ver `docs/privacidade.html`).
  Future<void> criarConvite({
    required String organizacaoId,
    required String email,
    required String role,
    bool consentimentoLgpd = false,
  }) {
    return _supabase.from('convites_familiares').insert({
      'organizacao_id': organizacaoId,
      'email_convidado': email,
      'role': role,
      'criado_por': _supabase.auth.currentUser!.id,
      if (consentimentoLgpd) 'consentimento_lgpd_em': DateTime.now().toIso8601String(),
    });
  }

  /// RLS de reenvio só permite update em convite ainda não aceito
  /// (`responsavel_reenvia_convite`) — reseta a expiração pra mais 7 dias.
  Future<void> reenviarConvite(String id) {
    return _supabase.from('convites_familiares').update({
      'expira_em': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
    }).eq('id', id);
  }

  Future<void> excluirConvite(String id) {
    return _supabase.from('convites_familiares').delete().eq('id', id);
  }
}
