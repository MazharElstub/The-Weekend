-- Phase 2: multi-calendar attribution for weekend events.
-- Allows one weekend event to appear in multiple planner calendars.

create table if not exists public.weekend_event_calendar_attributions (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null references public.weekend_events(id) on delete cascade,
    calendar_id uuid not null references public.planner_calendars(id) on delete cascade,
    user_id uuid not null,
    created_at timestamptz not null default now(),
    unique (event_id, calendar_id)
);

create index if not exists idx_weekend_event_attr_event
    on public.weekend_event_calendar_attributions(event_id);

create index if not exists idx_weekend_event_attr_calendar
    on public.weekend_event_calendar_attributions(calendar_id);

create index if not exists idx_weekend_event_attr_user
    on public.weekend_event_calendar_attributions(user_id);

-- Backfill: every event is at least attributed to its primary calendar.
insert into public.weekend_event_calendar_attributions (event_id, calendar_id, user_id)
select
    e.id,
    e.calendar_id,
    e.user_id
from public.weekend_events e
where e.calendar_id is not null
  and e.user_id is not null
on conflict (event_id, calendar_id) do nothing;

alter table public.weekend_event_calendar_attributions enable row level security;

drop policy if exists "weekend_event_attr_calendar_members_select" on public.weekend_event_calendar_attributions;
create policy "weekend_event_attr_calendar_members_select"
on public.weekend_event_calendar_attributions
for select
using (public.is_calendar_member(calendar_id));

drop policy if exists "weekend_event_attr_calendar_members_insert" on public.weekend_event_calendar_attributions;
create policy "weekend_event_attr_calendar_members_insert"
on public.weekend_event_calendar_attributions
for insert
with check (
    public.is_calendar_member(calendar_id)
    and user_id = auth.uid()
);

drop policy if exists "weekend_event_attr_calendar_members_delete" on public.weekend_event_calendar_attributions;
create policy "weekend_event_attr_calendar_members_delete"
on public.weekend_event_calendar_attributions
for delete
using (public.is_calendar_member(calendar_id));
