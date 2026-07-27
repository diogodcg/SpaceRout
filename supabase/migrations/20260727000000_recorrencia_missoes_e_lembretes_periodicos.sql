-- ============================================================================
-- Recorrência real de missões diárias/semanais + lembretes periódicos.
--
-- Até aqui, cada linha de coordenadas_voo era um ciclo único: depois de
-- aprovada/rejeitada, a missão nunca reaparecia (a criação automática do
-- próximo ciclo era um job futuro, nunca implementado — ver comentário em
-- app/lib/features/missoes/data/missoes_repository.dart). O lembrete à
-- criança também era único (1 push no horário notificar_as, sem repetição).
--
-- Esta migration prepara o schema para o job de reset diário
-- (supabase/functions/reiniciar_missoes_recorrentes) e para o lembrete
-- periódico (mudança em supabase/functions/enviar-lembretes-missao):
--   1. Novo status 'expirada' — ciclo diário/semanal que não foi cumprido
--      até o corte do dia (não fica em rollover indefinido).
--   2. Nova coluna primeiro_lembrete_em — guarda o horário do PRIMEIRO
--      lembrete (nunca sobrescrito), pra escalonamento continuar medindo
--      2h a partir do primeiro toque e não do último. lembrete_enviado_em
--      passa a significar "último lembrete enviado" (semântica muda, coluna
--      é a mesma).
--   3. relatorio_astronautas() recriada com uma coluna nova
--      missoes_expiradas, e missoes_em_aberto agora exclui 'expirada' (senão
--      missão perdida infla "em aberto" e confunde o responsável).
-- ============================================================================

alter type public.missao_status add value 'expirada';

alter table public.coordenadas_voo
    add column primeiro_lembrete_em timestamptz;

comment on column public.coordenadas_voo.primeiro_lembrete_em is
    'Horário do PRIMEIRO lembrete enviado ao astronauta (nunca sobrescrito) '
    '— base do cálculo de escalonamento (2h depois). lembrete_enviado_em '
    'guarda o último lembrete enviado (pode repetir enquanto "disponivel").';

comment on column public.coordenadas_voo.lembrete_enviado_em is
    'Horário do ÚLTIMO lembrete enviado ao astronauta. Atualizado a cada '
    'lembrete periódico (não só o primeiro) — ver primeiro_lembrete_em para '
    'o horário do primeiro toque.';
