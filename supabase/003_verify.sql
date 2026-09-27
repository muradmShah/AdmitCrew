-- Run after schema and seed. All temporary writes are rolled back.
-- On an error, execute ROLLBACK before running again.
begin;
do $$
declare student uuid; draft uuid; blocked boolean;
begin
    if (select count(*) from public.programs where is_practice_data) < 15 then
        raise exception 'Expected at least 15 practice programs';
    end if;
    if (select count(distinct country) from public.programs where is_practice_data) < 3 then
        raise exception 'Expected at least 3 countries';
    end if;
    if (select count(*) from public.leads where phone_normalized in ('923012345678','923339876543','923462223344')) <> 3 then
        raise exception 'Expected the three test students';
    end if;
    if not exists(select 1 from public.programs where university='University of Manchester'
        and program='BSc Computer Science' and fee_display='£32,000' and deadline='2027-01-15'
        and min_marks=75 and min_ielts=6.5 and required_documents=array['Passport','transcript','IELTS']) then
        raise exception 'Manchester data does not match the brief';
    end if;
    select id into student from public.leads where phone_normalized='923012345678';
    blocked := false;
    begin
        insert into public.leads(name,phone_normalized) values('Duplicate Ali','+92 301 2345678');
    exception when unique_violation then blocked := true;
    end;
    if not blocked then raise exception 'Duplicate number was not rejected'; end if;
    blocked := false;
    begin
        insert into public.leads(name,phone_normalized) values('Duplicate Ali','0092 301 2345678');
    exception when unique_violation then blocked := true;
    end;
    if not blocked then raise exception 'International prefix was not normalized'; end if;

    insert into public.leads(name,phone_normalized,country) values('Ali Khan','0301 2345678','UK')
    on conflict(phone_normalized) do update set country=excluded.country;
    if (select count(*) from public.leads where phone_normalized='923012345678') <> 1 then
        raise exception 'Upsert created a duplicate';
    end if;

    insert into public.messages(lead_id,direction,content,agent_name,idempotency_key)
    values(student,'outbound','Practice reply','advisor','qa:' || gen_random_uuid()) returning id into draft;
    if (select status from public.messages where id=draft) <> 'pending_approval' then
        raise exception 'Draft did not start pending';
    end if;
    blocked := false;
    begin
        update public.messages set status='sent',approved_at=now(),approved_by='QA',sent_at=now() where id=draft;
    exception when raise_exception then blocked := true;
    end;
    if not blocked then raise exception 'Draft skipped approval'; end if;
    blocked := false;
    begin
        insert into public.messages(lead_id,direction,content,status,approved_at,approved_by,sent_at)
        values(student,'outbound','Bad insert','sent',now(),'QA',now());
    exception when raise_exception then blocked := true;
    end;
    if not blocked then raise exception 'Insert bypassed approval'; end if;
    blocked := false;
    begin
        update public.messages set status='approved' where id=draft;
    exception when check_violation then blocked := true;
    end;
    if not blocked then raise exception 'Approval metadata was not required'; end if;

    update public.messages set status='approved',approved_at=now(),approved_by='QA staff' where id=draft;
    blocked := false;
    begin
        update public.messages set content='Unreviewed replacement' where id=draft;
    exception when raise_exception then blocked := true;
    end;
    if not blocked then raise exception 'Approved content was mutable'; end if;
    update public.messages set status='sent',sent_at=now() where id=draft;
    blocked := false;
    begin
        update public.messages set status='pending_approval',approved_at=null,approved_by=null,sent_at=null where id=draft;
    exception when raise_exception then blocked := true;
    end;
    if not blocked then raise exception 'Sent message was reopened'; end if;
    blocked := false;
    begin
        insert into public.messages(lead_id,direction,content,idempotency_key)
        select lead_id,direction,content,idempotency_key from public.messages where id=draft;
    exception when unique_violation then blocked := true;
    end;
    if not blocked then raise exception 'Duplicate draft key was accepted'; end if;
    if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname='public' and c.relname in ('programs','leads','messages') and not c.relrowsecurity) then
        raise exception 'RLS is missing';
    end if;
    if has_table_privilege('anon','public.leads','select')
       or has_table_privilege('authenticated','public.messages','insert') then
        raise exception 'Browser roles should not have access';
    end if;
    raise notice 'PASS: seed, normalization, upsert, approval lifecycle, immutable approval, draft deduplication, and access configuration';
end;
$$;
rollback;
