-- ============================================================================
-- Recria relatorio_astronautas() com uma coluna nova (missoes_expiradas) e
-- exclui 'expirada' de missoes_em_aberto (senão missão perdida contaria como
-- "em aberto" e confundiria o responsável). Precisa ser uma migration
-- separada da que adiciona o valor 'expirada' ao enum missao_status
-- (20260727000000), porque o Postgres não permite usar um valor de enum
-- recém-criado na mesma transação em que foi adicionado.
--
-- DROP + CREATE (não CREATE OR REPLACE) porque a lista de colunas retornadas
-- muda — Postgres não permite REPLACE de função quando o tipo de retorno
-- (RETURNS TABLE) é alterado.
-- ============================================================================

drop function public.relatorio_astronautas();

create function public.relatorio_astronautas()
returns table (
    astronauta_id uuid,
    nome_exibicao text,
    saldo_moedas integer,
    missoes_concluidas bigint,
    missoes_em_aberto bigint,
    missoes_expiradas bigint,
    premios_conquistados bigint
)
language sql
stable
security definer
set search_path = public
as $$
    select
        u.id,
        u.nome_exibicao,
        u.saldo_moedas,
        (select count(*) from public.coordenadas_voo cv where cv.atribuido_a = u.id and cv.status = 'aprovada'),
        (select count(*) from public.coordenadas_voo cv where cv.atribuido_a = u.id and cv.status not in ('aprovada', 'expirada')),
        (select count(*) from public.coordenadas_voo cv where cv.atribuido_a = u.id and cv.status = 'expirada'),
        (select count(*) from public.resgates_suprimentos r where r.resgatado_por = u.id and r.status = 'entregue')
    from public.usuarios u
    where u.organizacao_id = public.minha_organizacao_id()
      and u.role = 'astronauta'
    order by u.nome_exibicao;
$$;
