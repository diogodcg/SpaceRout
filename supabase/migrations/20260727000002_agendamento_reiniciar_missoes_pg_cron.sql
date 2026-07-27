-- ============================================================================
-- Agendamento do reinício diário de missões recorrentes.
-- A Edge Function (supabase/functions/reiniciar_missoes_recorrentes) faz a
-- varredura de fato; esta migration só cria o job pg_cron que a chama 1x/dia
-- via pg_net, logo depois da meia-noite em America/Sao_Paulo (Brasil não tem
-- mais horário de verão, então 00:05 local = 03:05 UTC o ano todo).
--
-- Mesmo padrão de autenticação de
-- 20260722000000_agendamento_lembretes_missao_pg_cron.sql: segredo lido do
-- Supabase Vault (vault.decrypted_secrets), nunca commitado aqui.
-- ============================================================================

select cron.schedule(
  'reiniciar-missoes-recorrentes',
  '5 3 * * *',
  $$
  select net.http_post(
    url := 'https://kzizdekhohisnixyzlqj.supabase.co/functions/v1/reiniciar_missoes_recorrentes',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'cron_shared_secret'
      )
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 15000
  ) as request_id;
  $$
);
