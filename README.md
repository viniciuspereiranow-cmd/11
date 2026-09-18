# Agenda Compartilhada

Aplicação web de agenda profissional compartilhada para Marina, Jéssica, Gabrielle Cardoso e Ana Clara.

## Stack
- React + TypeScript + Vite
- Supabase Auth + PostgreSQL + RLS + Realtime
- date-fns
- lucide-react

## Configuração do Supabase
1. Crie um projeto no Supabase.
2. Em Authentication, habilite **Anonymous Sign-Ins**.
3. Execute no SQL Editor o arquivo `supabase/migrations/001_initial.sql`.
4. Configure as variáveis:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_PUBLISHABLE_KEY`
5. Instale dependências e execute `npm run dev`.

O código inicial de acesso é `12345678p`. Ele não fica gravado em texto puro no frontend: a migração grava somente o hash no banco. Depois de entrar, qualquer profissional autorizada pode trocar o código em Configurações.

## Modelo de acesso
O sistema usa uma sessão anônima do Supabase para identificar tecnicamente cada navegador/sessão e um código compartilhado para autorizar o acesso. O perfil da profissional é uma camada separada e pode ser vinculada à sessão conforme a aplicação evoluir.

## Persistência
Agendamentos, clientes, serviços e configurações são armazenados no PostgreSQL. O banco também bloqueia conflitos de horário para a mesma profissional e mantém o agendamento cancelado como histórico.

## Importante
Nunca coloque uma service role key no frontend. Use apenas a chave publicável/anon do Supabase no cliente.
