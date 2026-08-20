# Leaderboard Online — F1 (com portas para F2/F3)

> Status: **desenho aprovado para implementação** · Escopo: bullet_veil (desafio diário)
> Autor: Léo + Claude · 2026-07-31

## 1. Contexto e fases

O jogo é offline-first. O desafio diário já roda com **seed determinística por data**
(todo mundo enfrenta as mesmas ondas) — isso é o alicerce de tudo aqui.

| Fase | Entrega | Objetivo |
|---|---|---|
| **F1** | Leaderboard online do diário, sem prêmio | Medir base real de jogadores; criar o músculo de operação |
| **F2** | Campeonato semanal com prêmio simbólico | Play Integrity + heurísticas + revisão manual do top 10 |
| **F3** | Temporadas automatizadas | Verificação de replay por re-simulação; ligas |

Decisões abaixo seguem o padrão Neutrino: **modular monolith, boring tech,
last responsible moment**. Nada de microsserviço, Kafka ou K8s — um dev solo,
tráfego desconhecido, dor inexistente ainda.

## 2. Decisões (ADR compacto)

**ADR-001 — Stack: Laravel + Postgres + Redis num VPS existente.**
Alternativa considerada: Cloudflare Worker + D1 (custo ~zero, zero ops).
Rejeitada porque a F3 precisa rodar o **verificador de replay em Dart** como
processo (re-simulação), o que exige runtime próprio — e a stack canônica da
casa é Laravel/Postgres, que o Léo opera com fluência. Um Worker seria um
segundo stack para morrer na F3. *Reversível? Sim (API pequena, contrato REST
estável) — decisão rápida, sem cerimônia extra.*

**ADR-002 — Sem contas de usuário na F1.**
Identidade = instalação: o app gera um par de chaves na primeira execução;
o servidor conhece só o **hash da chave pública** + nickname. Zero fricção,
zero PII (LGPD favorável). Conta social/e-mail só se a F2 exigir (prêmio real
precisa identificar o vencedor — e isso se coleta **fora do app**, só do
vencedor, na hora do pagamento).

**ADR-003 — Escopo `game` em toda tabela.**
Não é multi-tenant B2B (não há tenants), mas há **3 jogos no ecossistema**
(slash_frenzy, bullet_veil, stack_smash). `game text not null` em toda tabela
transacional + índices com `game` à esquerda = leaderboard dos três jogos no
mesmo serviço, de graça. É a versão honesta do `tenant_id` da KB para consumer.

**ADR-004 — Replay gravado desde a F1, verificado só na F3.**
O cliente já grava (implementado): posições a 20 Hz + eventos + seed +
checksum SHA-256. Na F1 o servidor só **armazena**. Na F2 roda heurísticas
sobre ele. Na F3 re-simula. Gravar desde o dia 1 significa que quando a F3
chegar, há **meses de dados reais** para calibrar heurísticas — e nenhuma
migração de formato no cliente.

## 3. C4 — Context + Container

```
┌─────────────────────────────  CONTEXT  ─────────────────────────────┐
│                                                                     │
│   [Jogador no Android] ──HTTPS──▶ [Leaderboard API]                 │
│        bullet_veil                 (VPS Neutrino)                   │
│        (Flutter, offline-first;    │                                │
│         fila local se sem rede)    ├──▶ [Play Integrity API] (F2)   │
│                                    └──▶ [Léo: revisão/pagamento]    │
└─────────────────────────────────────────────────────────────────────┘

┌───────────────────────────  CONTAINERS (VPS)  ──────────────────────┐
│  Caddy (TLS) ─▶ Laravel (API REST)                                  │
│                   ├─ Postgres 16  (players, runs, seasons)          │
│                   ├─ Redis        (cache de ranking, rate limit,    │
│                   │                fila de jobs)                    │
│                   └─ [F3] worker: `dart run verify_replay` (job)    │
│  docker compose · backup diário com RESTORE TESTADO                 │
└─────────────────────────────────────────────────────────────────────┘
```

## 4. Modelo de dados (Postgres, UUIDv7, timestamptz)

```sql
create table players (
  id               uuid primary key,            -- uuidv7 (servidor)
  game             text not null,
  device_key_hash  bytea not null,              -- sha-256 da pubkey do app
  nickname         text not null check (char_length(nickname) between 3 and 16),
  created_at       timestamptz not null default now(),
  banned_at        timestamptz
);
create unique index players_identity on players (game, device_key_hash);

create table runs (
  id               uuid primary key,            -- uuidv7; É o run_token
  player_id        uuid not null references players(id),
  game             text not null,
  mode             text not null,               -- 'daily' | 'season:<uuid>' (F2+)
  day              date not null,               -- dia do desafio
  seed             bigint not null,             -- AUTORIDADE DO SERVIDOR
  status           text not null default 'started',
                   -- started → submitted → verified | rejected
  score            integer,
  wave             integer,
  duration_s       integer,
  client_version   text not null,
  replay           bytea,                       -- gzip(json) — ver §6
  replay_sha256    bytea,
  integrity        jsonb,                       -- F2: veredito Play Integrity
  suspicion        numeric(5,2),                -- F2: score de heurísticas
  created_at       timestamptz not null default now(),
  submitted_at     timestamptz
);
-- ranking do dia: índice parcial já na ordem da consulta
create index runs_ranking on runs (game, mode, day, score desc)
  where status in ('submitted','verified');
-- uma tentativa por dia no diário (a regra do produto vira constraint)
create unique index runs_one_daily on runs (player_id, game, mode, day)
  where mode = 'daily';
```

Retenção de replay: 90 dias, exceto top-100 do dia e runs marcadas (mantém
custo de storage linear e material de calibração pra F3).

## 5. API (contrato v1)

```
POST /v1/players               {game, nickname, device_pubkey}
  → 201 {player_id}                                  rate: 3/dia por IP

POST /v1/runs                  {player_id, game, mode:'daily'}
  → 201 {run_id, day, seed}                          rate: 5/min
  ★ O SERVIDOR define a seed → o relógio do cliente deixa de mandar.
    (Offline: o app cai na seed local por data e NÃO submete.)

POST /v1/runs/{run_id}         {score, wave, duration_s, replay_b64,
                                replay_sha256, signature}
  → 200 {rank, percentile}                           rate: 5/min
  ★ signature = assinatura (chave do device) sobre score|wave|sha256.
    Invariantes checadas na hora: token existe e é dele; ainda 'started';
    duração plausível (± tolerância vs created_at); sha bate com o blob.

GET  /v1/leaderboards/daily?game=&day=
  → 200 {top: [ {rank, nickname, score, wave} ×100 ], me: {rank, score}}
  ★ Cache Redis 30s. Paginação por cursor (nunca OFFSET).
```

## 6. Formato do replay (v1 — já implementado no cliente)

```jsonc
{
  "v": 1,                    // versão do formato
  "game": "bullet_veil",
  "mode": "daily",
  "seed": 20260731,
  "hz": 20,                  // amostragem em RÉGUA FIXA de tempo de jogo
  "cv": "1.3.0+2004",        // client_version
  "score": 128400, "wave": 23, "dur": 512.3,
  "x": [360, 362, ...],      // posição da nave por amostra (int, px da arena)
  "y": [1020, 1018, ...],
  "ev": [ {"t": 214, "e": "bomb"}, ... ]   // t = índice da amostra
}
// serializado: gzip(json) → base64  ·  íntegro: sha-256 do json
```

**Honestidade técnica:** este formato permite, hoje, verificação por
**heurística forte** (continuidade de posição, limite de velocidade da nave,
bombas ≤ possuídas, curva de score plausível vs linha do tempo de ondas da
seed). A **re-simulação bit-exata** (F3) exige mover o loop do jogo para
timestep fixo e extrair a lógica para um package headless — refactor real,
planejado, não feito. O formato já carrega tudo que a re-simulação precisa
(seed + trajetória + eventos), então o refactor da F3 não muda o cliente.

## 7. Escada anti-fraude

| Fase | Defesa | Custo |
|---|---|---|
| F1 | Token de run emitido antes de jogar · seed do servidor · assinatura do device · duração plausível · rate limit · unique 1/dia | já no contrato |
| F2 | **Play Integrity API** (barra APK modificado/root/emulador) · heurísticas sobre o replay → `suspicion` · revisão manual do top 10 antes de pagar · ban por device_key | ~1 semana |
| F3 | Re-simulação: `dart run verify_replay <run_id>` num job da fila re-executa a partida e confere o score exato | o refactor de timestep fixo |

F1 não impede um atacante determinado — impede o **trivial** e coleta a
evidência. Prêmio real só entra com a F2 de pé (regra de negócio, não técnica).

## 8. LGPD e operação

- F1 não coleta PII: nickname livre (filtro de palavrões) + hash de chave.
- Vencedor (F2): nome/CPF/PIX coletados **fora do app**, só do vencedor,
  base legal execução de contrato, retenção mínima fiscal.
- Observabilidade mínima (padrão `neutrino-escala`): `/health`, uptime
  monitor externo, log estruturado de submits rejeitados (são o sinal).
- Backup: pg_dump diário + **restore ensaiado** antes do primeiro campeonato.

## 9. Fora de escopo (explícito)

Contas sociais, chat, clãs, espectador, anti-cheat kernel-level, prêmio em
dinheiro na F1, multi-região. Cada um só entra com dor medida.
