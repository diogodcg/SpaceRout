-- Modelo de negócio fechado em 2026-07-25 (ver README.md "Em aberto"):
--   - gatilho free→pago = itens ativos (3 missões + 3 suprimentos, era 5),
--     independente do tamanho da família — validado contra dados do IBGE
--     (família com 1-2 filhos é hoje maioria; um gatilho por nº de usuários
--     deixaria a família modal de graça pra sempre)
--   - preço da assinatura = tamanho de família, só depois de já ter
--     convertido: Tier 1 até 4 usuários, Tier 2 até 7 usuários
-- Esta migration cobre o modelo de dados; integração RevenueCat fica pra
-- uma etapa separada (é ela quem vai popular plano/plano_max_usuarios).

-- ============================================================================
-- TRAVA FREEMIUM: aperta de 5 para 3 itens ativos.
-- ============================================================================
create or replace function public.verificar_limite_freemium()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_plano public.plano_tipo;
    v_limite constant integer := 3;
    v_ativos integer;
begin
    select plano into v_plano
    from public.organizacoes_familiares
    where id = new.organizacao_id;

    if v_plano is distinct from 'gratuito' then
        return new;
    end if;

    if tg_table_name = 'coordenadas_voo' then
        if new.ativa is not true then
            return new;
        end if;
        if tg_op = 'UPDATE' and old.ativa is true then
            return new; -- já estava ativa, não é uma nova ativação
        end if;
        select count(*) into v_ativos
        from public.coordenadas_voo
        where organizacao_id = new.organizacao_id and ativa is true;

    elsif tg_table_name = 'suprimentos_cosmicos' then
        if new.ativo is not true then
            return new;
        end if;
        if tg_op = 'UPDATE' and old.ativo is true then
            return new;
        end if;
        select count(*) into v_ativos
        from public.suprimentos_cosmicos
        where organizacao_id = new.organizacao_id and ativo is true;
    end if;

    if v_ativos >= v_limite then
        raise exception
            'Plano gratuito permite no máximo % itens ativos em %',
            v_limite, tg_table_name
            using errcode = 'check_violation';
    end if;

    return new;
end;
$$;

-- ============================================================================
-- TAMANHO DE FAMÍLIA: quantos usuários (responsáveis + astronautas) o plano
-- pago da organização cobre. NULL enquanto 'gratuito' (sem teto de gente —
-- só o limite de itens acima gate-keeps o free). Passa a ser setado pelo
-- webhook do RevenueCat quando a assinatura é confirmada (próxima etapa).
-- ============================================================================
alter table public.organizacoes_familiares
    add column plano_max_usuarios integer;

comment on column public.organizacoes_familiares.plano_max_usuarios is
    'Teto de usuários do plano pago atual (4 = Tier 1, 7 = Tier 2). NULL '
    'enquanto gratuito — nesse plano não há limite de gente, só de itens '
    '(ver verificar_limite_freemium). Setado pelo webhook do RevenueCat.';

-- ============================================================================
-- TRAVA DE TAMANHO DE FAMÍLIA: aplicada na CRIAÇÃO DO CONVITE, não na tabela
-- usuarios. Motivo: a linha em usuarios é criada dentro de
-- aceitar_convite_no_login, que roda como trigger AFTER INSERT em
-- auth.users — uma exceção ali derrubaria a transação inteira de login/
-- cadastro do Supabase Auth, quebrando o app pro usuário convidado em vez
-- de mostrar um aviso amigável pra quem está convidando. Bloquear no
-- convite mantém o erro no lugar certo: uma ação normal do responsável,
-- coberta pelo mesmo padrão de erro amigável do limite de itens.
--
-- Conta usuários já ativos + convites pendentes não expirados, pra não
-- deixar convidar além do teto mesmo antes do convidado aceitar.
-- ============================================================================
create or replace function public.verificar_limite_usuarios_convite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_plano public.plano_tipo;
    v_max integer;
    v_total integer;
begin
    select plano, plano_max_usuarios into v_plano, v_max
    from public.organizacoes_familiares
    where id = new.organizacao_id;

    if v_plano is distinct from 'anual' or v_max is null then
        return new;
    end if;

    select
        (select count(*) from public.usuarios where organizacao_id = new.organizacao_id)
        + (select count(*) from public.convites_familiares
           where organizacao_id = new.organizacao_id
             and aceito = false
             and expira_em > now())
    into v_total;

    if v_total >= v_max then
        raise exception
            'Plano atual permite no máximo % usuários em convites_familiares',
            v_max
            using errcode = 'check_violation';
    end if;

    return new;
end;
$$;

create trigger trg_limite_usuarios_convite
    before insert on public.convites_familiares
    for each row execute function public.verificar_limite_usuarios_convite();
