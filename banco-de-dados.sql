-- © 2026 Samuel Inácio José. Todos os direitos reservados. Uso, cópia ou modificação somente com autorização. Ver LICENSE.
-- =====================================================================
-- Yury Peixoto Barbearia — banco de dados (Supabase)
-- Cole TUDO isto no Supabase: menu "SQL Editor" > "New query" > Run.
-- Pode rodar de novo sem problema: ele não apaga os agendamentos.
-- =====================================================================

-- Quem pode entrar no painel do Yury (e-mails autorizados)
create table if not exists public.admins (
  email text primary key
);

-- Configurações: barbeiros, serviços, preços, horário de funcionamento
create table if not exists public.config (
  id int primary key default 1 check (id = 1),
  dados jsonb not null
);

insert into public.config (id, dados) values (1, '{
  "barbeiros": ["Yury"],
  "equipe": [{"id": "yury", "nome": "Yury", "foto": "fotos/yury.webp", "ativo": true}],
  "servicos": [
    {"id": "corte",       "nome": "Corte",         "preco": 40, "duracao": 30},
    {"id": "barba",       "nome": "Barba",         "preco": 30, "duracao": 30},
    {"id": "corte-barba", "nome": "Corte + Barba", "preco": 65, "duracao": 60},
    {"id": "pezinho",     "nome": "Pezinho",       "preco": 15, "duracao": 15},
    {"id": "sobrancelha", "nome": "Sobrancelha",   "preco": 15, "duracao": 15}
  ],
  "abre": "09:00",
  "fecha": "19:00",
  "intervalo": 30,
  "diasAbertos": [2, 3, 4, 5, 6],
  "antecedenciaDias": 30,
  "pagamentos": ["Pix", "Dinheiro", "Cartão de débito", "Cartão de crédito"],
  "pixChave": ""
}'::jsonb)
on conflict (id) do nothing;

-- Dias bloqueados (folga, feriado) ou abertos fora do normal
create table if not exists public.dias (
  data date primary key,
  status text not null check (status in ('fechado', 'aberto')),
  motivo text not null default ''
);

-- Agendamentos
create table if not exists public.agendamentos (
  id uuid primary key default gen_random_uuid(),
  cliente text not null check (length(cliente) between 1 and 80),
  telefone text not null default '' check (length(telefone) <= 30),
  servico_id text not null,
  servico text not null,
  preco numeric(10,2) not null default 0,
  duracao int not null check (duracao between 5 and 480),
  barbeiro text not null,
  data date not null,
  hora text not null check (hora ~ '^[0-2][0-9]:[0-5][0-9]$'),
  obs text not null default '' check (length(obs) <= 300),
  status text not null default 'agendado' check (status in ('agendado', 'concluido', 'faltou', 'cancelado')),
  origem text not null default 'balcao' check (origem in ('site', 'balcao')),
  pagamento text not null default '' check (length(pagamento) <= 40),
  criado_em timestamptz not null default now()
);
-- (para quem já tinha o banco antes da forma de pagamento)
alter table public.agendamentos add column if not exists pagamento text not null default '' check (length(pagamento) <= 40);
update public.config
   set dados = jsonb_build_object('pagamentos', '["Pix", "Dinheiro", "Cartão de débito", "Cartão de crédito"]'::jsonb, 'pixChave', '') || dados
 where id = 1;
create index if not exists agendamentos_data_idx on public.agendamentos (data, barbeiro);

-- Equipe com foto (para quem já tinha o banco só com a lista de nomes).
-- "barbeiros" continua existindo: é a lista dos nomes ativos, que o painel mantém em dia.
update public.config
   set dados = dados || jsonb_build_object('equipe', coalesce((
         select jsonb_agg(jsonb_build_object(
                  'id', 'b' || t.ord,
                  'nome', t.b #>> '{}',
                  'foto', case when t.b #>> '{}' ilike 'yury%' then 'fotos/yury.webp' else '' end,
                  'ativo', true) order by t.ord)
           from jsonb_array_elements(dados -> 'barbeiros') with ordinality as t(b, ord)), '[]'::jsonb))
 where id = 1 and not dados ? 'equipe';

-- Horários bloqueados de um barbeiro (almoço, médico, folga de um barbeiro só).
-- Com "data": vale só naquele dia. Com "dia_semana" (0 = domingo): repete toda semana.
-- barbeiro = '*' vale para todos.
create table if not exists public.bloqueios (
  id uuid primary key default gen_random_uuid(),
  barbeiro text not null default '*' check (length(barbeiro) between 1 and 60),
  data date,
  dia_semana int check (dia_semana between 0 and 6),
  inicio text not null check (inicio ~ '^[0-2][0-9]:[0-5][0-9]$'),
  fim text not null check (fim ~ '^[0-2][0-9]:[0-5][0-9]$'),
  motivo text not null default '' check (length(motivo) <= 80),
  criado_em timestamptz not null default now(),
  check ((data is null) <> (dia_semana is null)),
  check (fim > inicio)
);
create index if not exists bloqueios_data_idx on public.bloqueios (data);

-- Financeiro (só o painel enxerga): % da barbearia sobre o que cada barbeiro arrecada
create table if not exists public.financeiro (
  id int primary key default 1 check (id = 1),
  dados jsonb not null default '{}'::jsonb
);
insert into public.financeiro (id, dados) values (1, '{"percentualPadrao": 40, "percentuais": {}}'::jsonb)
on conflict (id) do nothing;

-- Acertos: cada vez que o Yury tira a parte da barbearia de um período
create table if not exists public.acertos (
  id uuid primary key default gen_random_uuid(),
  barbeiro text not null,
  inicio date not null,
  fim date not null check (fim >= inicio),
  atendimentos int not null default 0,
  total numeric(10,2) not null default 0,
  percentual numeric(5,2) not null check (percentual between 0 and 100),
  valor_barbearia numeric(10,2) not null default 0,
  valor_barbeiro numeric(10,2) not null default 0,
  criado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Funções auxiliares
-- ---------------------------------------------------------------------
create or replace function public.minutos(h text) returns int
language sql immutable as $$
  select split_part(h, ':', 1)::int * 60 + split_part(h, ':', 2)::int
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  )
$$;

-- O painel usa isto para saber se o login é de um administrador
create or replace function public.sou_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin()
$$;

-- O site público vê só QUAIS horários estão ocupados — nunca nome, telefone ou motivo do bloqueio
create or replace function public.horarios_ocupados(p_inicio date, p_fim date)
returns table (data date, barbeiro text, hora text, duracao int)
language sql stable security definer set search_path = public as $$
  select a.data, a.barbeiro, a.hora, a.duracao
  from public.agendamentos a
  where a.data between p_inicio and least(p_fim, p_inicio + 62)
    and a.status in ('agendado', 'concluido')
  union all
  select g.dia::date, b.barbeiro, b.inicio, public.minutos(b.fim) - public.minutos(b.inicio)
  from generate_series(p_inicio, least(p_fim, p_inicio + 62), interval '1 day') as g(dia)
  join public.bloqueios b
    on b.data = g.dia::date
    or (b.data is null and b.dia_semana = extract(dow from g.dia)::int)
$$;

-- Versão antiga (sem forma de pagamento): o site não usa mais e ela não confere os bloqueios
drop function if exists public.criar_agendamento(text, text, text, text, date, text);

-- Agendamento feito pelo cliente no site. Confere tudo no servidor:
-- dia aberto, horário de funcionamento, horário livre, preço correto.
create or replace function public.criar_agendamento(
  p_cliente text, p_telefone text, p_servico_id text,
  p_barbeiro text, p_data date, p_hora text, p_pagamento text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  cfg jsonb;
  svc jsonb;
  v_tel text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_nome text := btrim(regexp_replace(coalesce(p_cliente, ''), '\s+', ' ', 'g'));
  v_ini int;
  v_fim int;
  v_dia record;
  v_aberto boolean;
  v_agora timestamp := now() at time zone 'America/Sao_Paulo';
  v_id uuid;
begin
  if length(v_nome) < 2 or length(v_nome) > 80 then
    raise exception 'Digite seu nome completo.';
  end if;
  if length(v_tel) < 10 or length(v_tel) > 13 then
    raise exception 'Digite um WhatsApp válido, com DDD.';
  end if;
  if p_hora is null or p_hora !~ '^[0-2][0-9]:[0-5][0-9]$' then
    raise exception 'Horário inválido.';
  end if;

  select dados into cfg from public.config where id = 1;

  select s into svc from jsonb_array_elements(cfg -> 'servicos') s where s ->> 'id' = p_servico_id;
  if svc is null then
    raise exception 'Serviço não encontrado. Atualize a página.';
  end if;
  if not (cfg -> 'barbeiros') ? p_barbeiro then
    raise exception 'Barbeiro não encontrado. Atualize a página.';
  end if;
  if jsonb_array_length(coalesce(cfg -> 'pagamentos', '[]'::jsonb)) > 0
     and not (cfg -> 'pagamentos') ? coalesce(p_pagamento, '') then
    raise exception 'Escolha a forma de pagamento.';
  end if;

  v_ini := public.minutos(p_hora);
  v_fim := v_ini + (svc ->> 'duracao')::int;
  if v_ini < public.minutos(cfg ->> 'abre') or v_fim > public.minutos(cfg ->> 'fecha') then
    raise exception 'Esse horário está fora do funcionamento da barbearia.';
  end if;
  if (p_data + p_hora::time) <= v_agora then
    raise exception 'Esse horário já passou. Escolha outro.';
  end if;
  if p_data > v_agora::date + coalesce((cfg ->> 'antecedenciaDias')::int, 30) then
    raise exception 'Ainda não abrimos a agenda para essa data.';
  end if;

  select * into v_dia from public.dias where dias.data = p_data;
  if found then
    v_aberto := v_dia.status = 'aberto';
  else
    v_aberto := (cfg -> 'diasAbertos') @> jsonb_build_array(extract(dow from p_data)::int);
  end if;
  if not v_aberto then
    raise exception 'A barbearia não abre nesse dia. Escolha outra data.';
  end if;

  -- Limite contra abuso: no máximo 2 horários futuros por telefone
  if (select count(*) from public.agendamentos a
      where regexp_replace(a.telefone, '\D', '', 'g') = v_tel
        and a.status = 'agendado'
        and a.data >= v_agora::date) >= 2 then
    raise exception 'Você já tem horários marcados. Para mudar, fale com a barbearia no WhatsApp.';
  end if;

  if exists (
    select 1 from public.bloqueios b
    where b.barbeiro in ('*', p_barbeiro)
      and (b.data = p_data or (b.data is null and b.dia_semana = extract(dow from p_data)::int))
      and public.minutos(b.inicio) < v_fim
      and public.minutos(b.fim) > v_ini
  ) then
    raise exception 'Esse horário não está disponível. Escolha outro.';
  end if;

  -- Trava para dois clientes não pegarem o mesmo horário ao mesmo tempo
  perform pg_advisory_xact_lock(hashtext(p_barbeiro || '|' || p_data::text));
  if exists (
    select 1 from public.agendamentos a
    where a.data = p_data and a.barbeiro = p_barbeiro
      and a.status in ('agendado', 'concluido')
      and public.minutos(a.hora) < v_fim
      and public.minutos(a.hora) + a.duracao > v_ini
  ) then
    raise exception 'Alguém acabou de pegar esse horário. Escolha outro.';
  end if;

  insert into public.agendamentos (cliente, telefone, servico_id, servico, preco, duracao, barbeiro, data, hora, status, origem, pagamento)
  values (v_nome, p_telefone, p_servico_id, svc ->> 'nome', (svc ->> 'preco')::numeric,
          (svc ->> 'duracao')::int, p_barbeiro, p_data, p_hora, 'agendado', 'site', coalesce(p_pagamento, ''))
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Segurança (RLS): o público não lê dados de clientes
-- ---------------------------------------------------------------------
alter table public.admins       enable row level security;
alter table public.config       enable row level security;
alter table public.dias         enable row level security;
alter table public.agendamentos enable row level security;
alter table public.bloqueios    enable row level security;
alter table public.financeiro   enable row level security;
alter table public.acertos      enable row level security;

drop policy if exists "config: todos leem"      on public.config;
drop policy if exists "config: admin altera"    on public.config;
drop policy if exists "dias: todos leem"        on public.dias;
drop policy if exists "dias: admin altera"      on public.dias;
drop policy if exists "agendamentos: só admin"  on public.agendamentos;
drop policy if exists "bloqueios: só admin"     on public.bloqueios;
drop policy if exists "financeiro: só admin"    on public.financeiro;
drop policy if exists "acertos: só admin"       on public.acertos;

create policy "config: todos leem"     on public.config       for select using (true);
create policy "config: admin altera"   on public.config       for update using (public.is_admin()) with check (public.is_admin());
create policy "dias: todos leem"       on public.dias         for select using (true);
create policy "dias: admin altera"     on public.dias         for all    using (public.is_admin()) with check (public.is_admin());
create policy "agendamentos: só admin" on public.agendamentos for all    using (public.is_admin()) with check (public.is_admin());
create policy "bloqueios: só admin"    on public.bloqueios    for all    using (public.is_admin()) with check (public.is_admin());
create policy "financeiro: só admin"   on public.financeiro   for all    using (public.is_admin()) with check (public.is_admin());
create policy "acertos: só admin"      on public.acertos      for all    using (public.is_admin()) with check (public.is_admin());
-- (o site público vê os bloqueios só pela função horarios_ocupados, sem o motivo)
-- (a tabela admins não tem política: ninguém lê nem altera pelo site)

revoke all on function public.criar_agendamento(text, text, text, text, date, text, text) from public;
revoke all on function public.horarios_ocupados(date, date) from public;
grant execute on function public.criar_agendamento(text, text, text, text, date, text, text) to anon, authenticated;
grant execute on function public.horarios_ocupados(date, date) to anon, authenticated;
grant execute on function public.sou_admin() to authenticated;

-- Fotos dos barbeiros (pasta pública "fotos"; só o painel envia ou apaga)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 3145728, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;
drop policy if exists "fotos: admin vê"    on storage.objects;
drop policy if exists "fotos: admin envia" on storage.objects;
drop policy if exists "fotos: admin troca" on storage.objects;
drop policy if exists "fotos: admin apaga" on storage.objects;
create policy "fotos: admin vê"    on storage.objects for select to authenticated using (bucket_id = 'fotos' and public.is_admin());
create policy "fotos: admin envia" on storage.objects for insert to authenticated with check (bucket_id = 'fotos' and public.is_admin());
create policy "fotos: admin troca" on storage.objects for update to authenticated using (bucket_id = 'fotos' and public.is_admin());
create policy "fotos: admin apaga" on storage.objects for delete to authenticated using (bucket_id = 'fotos' and public.is_admin());

-- Atualização ao vivo no painel quando entra agendamento pelo site
do $$
begin
  begin
    alter publication supabase_realtime add table public.agendamentos;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.dias;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.config;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.bloqueios;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.acertos;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.financeiro;
  exception when duplicate_object then null;
  end;
end $$;

-- =====================================================================
-- ÚLTIMO PASSO: troque o e-mail abaixo pelo e-mail do Yury e rode só
-- esta linha (selecione e clique em Run):
--
-- insert into public.admins (email) values ('email-do-yury@gmail.com');
-- =====================================================================
