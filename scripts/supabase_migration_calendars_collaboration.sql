-- Multi-calendar collaboration migration
-- Supports personal + shared calendars with up to 5 members.

create table if not exists public.planner_calendars (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    owner_user_id uuid not null,
    share_code text not null unique,
    max_members integer not null default 5 check (max_members between 1 and 5),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.calendar_members (
    id uuid primary key default gen_random_uuid(),
    calendar_id uuid not null references public.planner_calendars(id) on delete cascade,
    user_id uuid not null,
    role text not null default 'member' check (role in ('owner','member')),
    created_at timestamptz not null default now(),
    unique (calendar_id, user_id)
);

create index if not exists idx_calendar_members_user on public.calendar_members(user_id);
create index if not exists idx_calendar_members_calendar on public.calendar_members(calendar_id);

create or replace function public.set_planner_calendars_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_planner_calendars_set_updated_at on public.planner_calendars;
create trigger trg_planner_calendars_set_updated_at
before update on public.planner_calendars
for each row
execute function public.set_planner_calendars_updated_at();

create or replace function public.enforce_calendar_member_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    current_count integer;
    allowed_max integer;
begin
    select count(*) into current_count
    from public.calendar_members
    where calendar_id = new.calendar_id;

    select max_members into allowed_max
    from public.planner_calendars
    where id = new.calendar_id;

    if allowed_max is null then
        raise exception 'Calendar not found';
    end if;

    if current_count >= allowed_max then
        raise exception 'Calendar member limit reached (% max)', allowed_max;
    end if;

    return new;
end;
$$;

create or replace function public.is_calendar_member(target_calendar_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1
        from public.calendar_members m
        where m.calendar_id = target_calendar_id
          and m.user_id = auth.uid()
    );
$$;

create or replace function public.is_calendar_owner(target_calendar_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1
        from public.planner_calendars c
        where c.id = target_calendar_id
          and c.owner_user_id = auth.uid()
    );
$$;

drop trigger if exists trg_calendar_members_member_limit on public.calendar_members;
create trigger trg_calendar_members_member_limit
before insert on public.calendar_members
for each row
execute function public.enforce_calendar_member_limit();

alter table if exists public.weekend_events
    add column if not exists calendar_id uuid references public.planner_calendars(id) on delete cascade;

alter table if exists public.weekend_protections
    add column if not exists calendar_id uuid references public.planner_calendars(id) on delete cascade;

create index if not exists idx_weekend_events_calendar on public.weekend_events(calendar_id);
create index if not exists idx_weekend_protections_calendar on public.weekend_protections(calendar_id);

-- Backfill personal calendars for existing users.
with existing_users as (
    select distinct user_id from public.weekend_events where user_id is not null
    union
    select distinct user_id from public.weekend_protections where user_id is not null
)
insert into public.planner_calendars (name, owner_user_id, share_code, max_members)
select
    'Personal',
    u.user_id,
    upper(substr(md5(gen_random_uuid()::text), 1, 8)),
    5
from existing_users u
where not exists (
    select 1
    from public.planner_calendars c
    where c.owner_user_id = u.user_id
      and c.name = 'Personal'
);

insert into public.calendar_members (calendar_id, user_id, role)
select c.id, c.owner_user_id, 'owner'
from public.planner_calendars c
where not exists (
    select 1
    from public.calendar_members m
    where m.calendar_id = c.id
      and m.user_id = c.owner_user_id
);

with personal as (
    select distinct on (owner_user_id)
        owner_user_id,
        id as calendar_id
    from public.planner_calendars
    where name = 'Personal'
    order by owner_user_id, created_at asc, id asc
)
update public.weekend_events e
set calendar_id = p.calendar_id
from personal p
where e.calendar_id is null
  and e.user_id = p.owner_user_id;

with personal as (
    select distinct on (owner_user_id)
        owner_user_id,
        id as calendar_id
    from public.planner_calendars
    where name = 'Personal'
    order by owner_user_id, created_at asc, id asc
)
update public.weekend_protections p0
set calendar_id = p.calendar_id
from personal p
where p0.calendar_id is null
  and p0.user_id = p.owner_user_id;

alter table public.planner_calendars enable row level security;
alter table public.calendar_members enable row level security;

-- Members can read calendars they belong to.
drop policy if exists "planner_calendars_select_members" on public.planner_calendars;
create policy "planner_calendars_select_members" on public.planner_calendars
for select
using (public.is_calendar_member(id));

-- Owners can create/update/delete their calendars.
drop policy if exists "planner_calendars_insert_owner" on public.planner_calendars;
create policy "planner_calendars_insert_owner" on public.planner_calendars
for insert
with check (owner_user_id = auth.uid());

drop policy if exists "planner_calendars_update_owner" on public.planner_calendars;
create policy "planner_calendars_update_owner" on public.planner_calendars
for update
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

drop policy if exists "planner_calendars_delete_owner" on public.planner_calendars;
create policy "planner_calendars_delete_owner" on public.planner_calendars
for delete
using (owner_user_id = auth.uid());

-- Members table policies.
drop policy if exists "calendar_members_select_members" on public.calendar_members;
create policy "calendar_members_select_members" on public.calendar_members
for select
using (
    user_id = auth.uid()
    or public.is_calendar_member(calendar_id)
);

drop policy if exists "calendar_members_insert_self_or_owner" on public.calendar_members;
create policy "calendar_members_insert_self_or_owner" on public.calendar_members
for insert
with check (
    user_id = auth.uid()
    or public.is_calendar_owner(calendar_id)
);

drop policy if exists "calendar_members_delete_self_or_owner" on public.calendar_members;
create policy "calendar_members_delete_self_or_owner" on public.calendar_members
for delete
using (
    user_id = auth.uid()
    or public.is_calendar_owner(calendar_id)
);

-- Weekend events/protections: any member of the calendar can read/write.
drop policy if exists "weekend_events_calendar_members" on public.weekend_events;
create policy "weekend_events_calendar_members" on public.weekend_events
for all
using (public.is_calendar_member(weekend_events.calendar_id))
with check (public.is_calendar_member(weekend_events.calendar_id));

drop policy if exists "weekend_protections_calendar_members" on public.weekend_protections;
create policy "weekend_protections_calendar_members" on public.weekend_protections
for all
using (public.is_calendar_member(weekend_protections.calendar_id))
with check (public.is_calendar_member(weekend_protections.calendar_id));
