-- Fase 3: permite ao banco fazer chamadas web (usado no teste da Edge
-- Function foto-assinada; será usado também no keep-alive e nas notificações).
create extension if not exists pg_net with schema extensions;
