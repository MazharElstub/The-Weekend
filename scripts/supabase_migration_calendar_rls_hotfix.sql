-- Calendar RLS hotfix
-- Ensures planner calendar creation works under RLS.

alter table if exists public.planner_calendars enable row level security;

-- Remove any legacy/unknown policies so command-specific policies are authoritative.
do $$
declare
    pol record;
begin
    for pol in
        select policyname
        from pg_policies
        where schemaname = 'public'
          and tablename = 'planner_calendars'
    loop
        execute format('drop policy if exists %I on public.planner_calendars;', pol.policyname);
    end loop;
end
$$;

-- Members and owners can read; owners create/update/delete.
create policy "planner_calendars_select_members_or_owner"
on public.planner_calendars
for select
using (
    owner_user_id = auth.uid()
    or public.is_calendar_member(id)
);

create policy "planner_calendars_insert_owner"
on public.planner_calendars
for insert
with check (owner_user_id = auth.uid());

create policy "planner_calendars_update_owner"
on public.planner_calendars
for update
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

create policy "planner_calendars_delete_owner"
on public.planner_calendars
for delete
using (owner_user_id = auth.uid());
