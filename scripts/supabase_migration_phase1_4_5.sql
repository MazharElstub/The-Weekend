-- WeekendPlannerIOS migration: phase 1 + phase 4 + phase 5

-- 1) weekend_events lifecycle columns
alter table if exists public.weekend_events
    add column if not exists status text default 'planned',
    add column if not exists completed_at timestamptz,
    add column if not exists cancelled_at timestamptz,
    add column if not exists client_updated_at timestamptz default now(),
    add column if not exists updated_at timestamptz default now(),
    add column if not exists created_at timestamptz default now(),
    add column if not exists deleted_at timestamptz;

alter table if exists public.weekend_events
    drop constraint if exists weekend_events_status_check;

alter table if exists public.weekend_events
    add constraint weekend_events_status_check check (status in ('planned', 'completed', 'cancelled'));

create index if not exists idx_weekend_events_user_weekend
    on public.weekend_events(user_id, weekend_key);

create index if not exists idx_weekend_events_user_updated
    on public.weekend_events(user_id, updated_at desc);

create index if not exists idx_weekend_events_user_deleted
    on public.weekend_events(user_id, deleted_at);

create or replace function public.set_weekend_events_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_weekend_events_set_updated_at on public.weekend_events;
create trigger trg_weekend_events_set_updated_at
before update on public.weekend_events
for each row
execute function public.set_weekend_events_updated_at();

-- 2) template bundles
create table if not exists public.plan_template_bundles (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.plan_template_bundle_items (
    id uuid primary key default gen_random_uuid(),
    bundle_id uuid not null references public.plan_template_bundles(id) on delete cascade,
    title text not null,
    type text not null,
    days text[] not null,
    start_time text not null,
    end_time text not null,
    sort_order integer not null default 0,
    created_at timestamptz not null default now()
);

-- 3) audit logs
create table if not exists public.event_audit_logs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    action text not null,
    entity_type text not null,
    entity_id text not null,
    payload jsonb not null default '{}'::jsonb,
    occurred_at timestamptz not null default now()
);

-- 4) monthly goals
create table if not exists public.monthly_goals (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    month_key text not null,
    planned_target integer not null,
    completed_target integer not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique(user_id, month_key)
);

create or replace function public.set_monthly_goals_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_monthly_goals_set_updated_at on public.monthly_goals;
create trigger trg_monthly_goals_set_updated_at
before update on public.monthly_goals
for each row
execute function public.set_monthly_goals_updated_at();

-- 5) RLS
alter table public.plan_template_bundles enable row level security;
alter table public.plan_template_bundle_items enable row level security;
alter table public.event_audit_logs enable row level security;
alter table public.monthly_goals enable row level security;

drop policy if exists "plan_template_bundles_owner" on public.plan_template_bundles;
create policy "plan_template_bundles_owner" on public.plan_template_bundles
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "plan_template_bundle_items_owner" on public.plan_template_bundle_items;
create policy "plan_template_bundle_items_owner" on public.plan_template_bundle_items
for all
using (
    exists (
        select 1
        from public.plan_template_bundles b
        where b.id = bundle_id
          and b.user_id = auth.uid()
    )
)
with check (
    exists (
        select 1
        from public.plan_template_bundles b
        where b.id = bundle_id
          and b.user_id = auth.uid()
    )
);

drop policy if exists "event_audit_logs_owner" on public.event_audit_logs;
create policy "event_audit_logs_owner" on public.event_audit_logs
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "monthly_goals_owner" on public.monthly_goals;
create policy "monthly_goals_owner" on public.monthly_goals
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
