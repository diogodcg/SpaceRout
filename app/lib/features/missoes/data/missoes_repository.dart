import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Cadastro de missões e aprovação de comprovações pelo responsável
/// (`coordenadas_voo`). Envio de comprovação pelo astronauta passa pela RPC
/// `enviar_comprovacao_missao` (não por aqui) — ver PLANO_MIGRACAO.md §5.5.2.
/// Cada linha é um ciclo de missão; a criação automática do próximo ciclo
/// (recorrência) é feita pela Edge Function
/// `reiniciar_missoes_recorrentes` (1x/dia via pg_cron), não por aqui.
class MissoesRepository {
  MissoesRepository(this._supabase);

  final SupabaseClient _supabase;

  /// Só o ciclo atual de cada missão (`ativa = true`) — com a recorrência
  /// automática (ver `reiniciar_missoes_recorrentes`), cada missão diária/
  /// semanal gera uma linha nova por ciclo e arquiva a anterior
  /// (`ativa = false`), então listar tudo sem filtro viraria um histórico
  /// crescente sem fim. O histórico completo por astronauta já existe em
  /// `relatorio_astronautas()`.
  Future<List<Map<String, dynamic>>> listarMissoes() async {
    final rows = await _supabase
        .from('coordenadas_voo')
        .select()
        .eq('ativa', true)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> listarComprovacoesPendentes() async {
    final rows = await _supabase
        .from('coordenadas_voo')
        .select()
        .eq('status', 'enviada')
        .order('data_envio', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// `astronautaIds` vazio cria 1 linha aberta pra qualquer um; com um ou
  /// mais, cria uma linha independente por astronauta selecionado — cada
  /// uma com seu próprio ciclo de comprovação/aprovação, editada
  /// separadamente (ver [atualizarMissao]).
  Future<void> criarMissao({
    required String organizacaoId,
    required String titulo,
    required int moedas,
    required String recorrencia,
    required List<String> astronautaIds,
  }) {
    final criadoPor = _supabase.auth.currentUser!.id;
    final atribuicoes = astronautaIds.isEmpty ? const [null] : astronautaIds;
    return _supabase.from('coordenadas_voo').insert([
      for (final astronautaId in atribuicoes)
        {
          'organizacao_id': organizacaoId,
          'titulo': titulo,
          'moedas': moedas,
          'recorrencia': recorrencia,
          'criado_por': criadoPor,
          'atribuido_a': astronautaId,
        },
    ]);
  }

  /// Atribuição não é editável (ver [MissaoFormScreen]) — só título, moedas
  /// e recorrência, e só da linha em questão (cada astronauta atribuído
  /// junto na criação é editado separadamente).
  Future<void> atualizarMissao(
    String id, {
    required String titulo,
    required int moedas,
    required String recorrencia,
  }) {
    return _supabase.from('coordenadas_voo').update({
      'titulo': titulo,
      'moedas': moedas,
      'recorrencia': recorrencia,
    }).eq('id', id);
  }

  Future<void> definirAtiva(String id, bool ativa) {
    return _supabase.from('coordenadas_voo').update({'ativa': ativa}).eq('id', id);
  }

  /// RLS só permite excluir missões com `status = 'disponivel'` (nunca
  /// enviadas/aprovadas) — preserva a trilha de auditoria de moedas já
  /// creditadas. Ver migration `20260719220000_exclusao_missoes_disponiveis`.
  Future<void> excluirMissao(String id) {
    return _supabase.from('coordenadas_voo').delete().eq('id', id);
  }

  Future<void> validarComprovacao(String id, {required bool aprovada}) {
    return _supabase.from('coordenadas_voo').update({
      'status': aprovada ? 'aprovada' : 'rejeitada',
      'validado_por': _supabase.auth.currentUser!.id,
      'data_validacao': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// Lookup de `nome_exibicao` por id, usado para mostrar quem enviou cada
  /// comprovação sem precisar lidar com embedding ambíguo do PostgREST
  /// (coordenadas_voo tem múltiplas FKs para usuarios).
  Future<Map<String, String>> nomesUsuarios(Iterable<String> ids) async {
    final idsUnicos = ids.toSet().toList();
    if (idsUnicos.isEmpty) return {};
    final rows = await _supabase
        .from('usuarios')
        .select('id, nome_exibicao')
        .inFilter('id', idsUnicos);
    return {
      for (final row in rows) row['id'] as String: row['nome_exibicao'] as String,
    };
  }

  /// Bucket `comprovacoes` é privado — precisa de URL assinada para exibir a
  /// foto. `foto_url` guarda o path, não uma URL pronta.
  Future<String> urlAssinadaComprovacao(String path) {
    return _supabase.storage.from('comprovacoes').createSignedUrl(path, 3600);
  }

  /// Missões relevantes pro astronauta logado: em aberto pra qualquer um
  /// (`atribuido_a` nulo) ou atribuídas a ele — inclui as que ele mesmo já
  /// enviou/teve aprovadas/rejeitadas, pra servir de histórico/feedback.
  Future<List<Map<String, dynamic>>> listarMissoesAstronauta() async {
    final uid = _supabase.auth.currentUser!.id;
    final rows = await _supabase
        .from('coordenadas_voo')
        .select()
        .eq('ativa', true)
        .or('atribuido_a.eq.$uid,atribuido_a.is.null')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Upload da foto (bucket privado `comprovacoes`, path
  /// `{organizacao_id}/{missao_id}.{extensao}` — ver storage policies) e
  /// chamada da RPC `enviar_comprovacao_missao`, que valida atribuição/status
  /// e é o único jeito do astronauta mudar status/foto_url (RLS não permite
  /// UPDATE direto por ele — ver PLANO_MIGRACAO.md §5.5.2).
  Future<void> enviarComprovacao({
    required String organizacaoId,
    required String missaoId,
    required Uint8List bytes,
    required String extensao,
  }) async {
    final path = '$organizacaoId/$missaoId.$extensao';
    await _supabase.storage
        .from('comprovacoes')
        .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
    await _supabase.rpc('enviar_comprovacao_missao', params: {
      'p_missao_id': missaoId,
      'p_foto_url': path,
    });
  }
}
