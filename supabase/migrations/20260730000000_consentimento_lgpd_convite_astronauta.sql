-- A política de privacidade (docs/privacidade.html, seção "Crianças e
-- contas de família") afirma que convidar um astronauta (criança/
-- adolescente) concede o "consentimento específico e destacado" exigido
-- pelo art. 14 da LGPD. Até aqui isso não tinha nenhum respaldo no
-- produto: a tela de convite não pedia nada além do e-mail e do papel.
-- Esta coluna registra quando esse consentimento foi de fato dado, e o
-- check constraint garante no banco (não só na UI) que todo convite de
-- astronauta tem esse timestamp.
alter table convites_familiares
  add column consentimento_lgpd_em timestamptz;

alter table convites_familiares
  add constraint consentimento_lgpd_obrigatorio_para_astronauta
  check (role <> 'astronauta' or consentimento_lgpd_em is not null);
