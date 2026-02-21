-- Phase 3: account deletion compliance + member notices.

create table if not exists public.user_notices (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    type text not null,
    title text not null,
    message text not null,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    read_at timestamptz
);

create index if not exists idx_user_notices_user_created
    on public.user_notices(user_id, created_at desc);

create index if not exists idx_user_notices_user_unread
    on public.user_notices(user_id)
    where read_at is null;

alter table public.user_notices enable row level security;

drop policy if exists "user_notices_select_own" on public.user_notices;
create policy "user_notices_select_own"
on public.user_notices
for select
using (user_id = auth.uid());

drop policy if exists "user_notices_update_own" on public.user_notices;
create policy "user_notices_update_own"
on public.user_notices
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

create or replace function public.mark_notice_read(p_notice_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
begin
    if v_user_id is null then
        raise exception 'Not authenticated';
    end if;

    update public.user_notices
    set read_at = coalesce(read_at, now())
    where id = p_notice_id
      and user_id = v_user_id;

    return found;
end;
$$;

revoke all on function public.mark_notice_read(uuid) from public;
grant execute on function public.mark_notice_read(uuid) to authenticated;

create or replace function public.delete_my_account(p_ownership_mode text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_user_id uuid := auth.uid();
    v_calendar record;
    v_new_owner_id uuid;
    v_notices_inserted integer;
    v_transferred_calendar_count integer := 0;
    v_deleted_calendar_count integer := 0;
    v_notices_created_count integer := 0;
begin
    if v_user_id is null then
        raise exception 'Not authenticated';
    end if;

    if p_ownership_mode not in ('transfer', 'delete') then
        raise exception 'Invalid ownership mode: %', p_ownership_mode
            using errcode = '22023';
    end if;

    for v_calendar in
        select id, name
        from public.planner_calendars
        where owner_user_id = v_user_id
        order by created_at asc
    loop
        v_new_owner_id := null;

        if p_ownership_mode = 'transfer' then
            select m.user_id
            into v_new_owner_id
            from public.calendar_members m
            where m.calendar_id = v_calendar.id
              and m.user_id <> v_user_id
            order by m.created_at asc
            limit 1;
        end if;

        if v_new_owner_id is not null then
            update public.planner_calendars
            set owner_user_id = v_new_owner_id
            where id = v_calendar.id;

            update public.calendar_members
            set role = case
                when user_id = v_new_owner_id then 'owner'
                else 'member'
            end
            where calendar_id = v_calendar.id
              and role in ('owner', 'member');

            v_transferred_calendar_count := v_transferred_calendar_count + 1;
        else
            insert into public.user_notices (
                user_id,
                type,
                title,
                message,
                metadata
            )
            select
                m.user_id,
                'calendar_deleted',
                'Shared calendar removed',
                format(
                    '"%s" was removed because the owner deleted their account.',
                    v_calendar.name
                ),
                jsonb_build_object(
                    'calendar_id', v_calendar.id::text,
                    'calendar_name', v_calendar.name,
                    'former_owner_user_id', v_user_id::text,
                    'reason', 'owner_deleted_account'
                )
            from public.calendar_members m
            where m.calendar_id = v_calendar.id
              and m.user_id <> v_user_id;

            get diagnostics v_notices_inserted = row_count;
            v_notices_created_count := v_notices_created_count + coalesce(v_notices_inserted, 0);

            delete from public.planner_calendars
            where id = v_calendar.id;

            v_deleted_calendar_count := v_deleted_calendar_count + 1;
        end if;
    end loop;

    delete from public.calendar_members
    where user_id = v_user_id;

    delete from public.weekend_event_calendar_attributions
    where user_id = v_user_id;

    delete from public.weekend_events
    where user_id = v_user_id;

    delete from public.weekend_protections
    where user_id = v_user_id;

    delete from public.monthly_goals
    where user_id = v_user_id;

    delete from public.plan_template_bundles
    where user_id = v_user_id;

    delete from public.event_audit_logs
    where user_id = v_user_id;

    delete from public.user_notices
    where user_id = v_user_id;

    delete from auth.users
    where id = v_user_id;

    return jsonb_build_object(
        'deleted_user_id', v_user_id::text,
        'transferred_calendar_count', v_transferred_calendar_count,
        'deleted_calendar_count', v_deleted_calendar_count,
        'notices_created_count', v_notices_created_count
    );
end;
$$;

revoke all on function public.delete_my_account(text) from public;
grant execute on function public.delete_my_account(text) to authenticated;
