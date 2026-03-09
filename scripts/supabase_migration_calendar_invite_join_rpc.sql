-- Calendar invite join RPC
-- Allows authenticated users to join a shared calendar by share code under RLS.

create or replace function public.join_calendar_by_share_code(p_share_code text)
returns table (
    calendar_id uuid,
    calendar_name text,
    membership_created boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
    normalized_code text;
    target_calendar public.planner_calendars%rowtype;
    current_member_count integer;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    normalized_code := upper(regexp_replace(coalesce(p_share_code, ''), '[^A-Za-z0-9]', '', 'g'));
    if normalized_code = '' then
        raise exception 'Share code is required';
    end if;

    select *
    into target_calendar
    from public.planner_calendars c
    where upper(c.share_code) = normalized_code
    limit 1;

    if not found then
        raise exception 'No calendar found for code %', normalized_code;
    end if;

    if exists (
        select 1
        from public.calendar_members m
        where m.calendar_id = target_calendar.id
          and m.user_id = auth.uid()
    ) then
        return query
        select target_calendar.id, target_calendar.name, false;
        return;
    end if;

    select count(*)
    into current_member_count
    from public.calendar_members m
    where m.calendar_id = target_calendar.id;

    if current_member_count >= target_calendar.max_members then
        raise exception 'This calendar is full. A maximum of % members is allowed.', target_calendar.max_members;
    end if;

    begin
        insert into public.calendar_members (calendar_id, user_id, role)
        values (target_calendar.id, auth.uid(), 'member');
    exception
        when unique_violation then
            null;
    end;

    return query
    select target_calendar.id, target_calendar.name, true;
end;
$$;

revoke all on function public.join_calendar_by_share_code(text) from public;
grant execute on function public.join_calendar_by_share_code(text) to authenticated;
