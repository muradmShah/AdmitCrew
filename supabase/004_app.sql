-- Run once AFTER 001 and 002. Adds the full app's records and atomic demo delivery.
begin;
alter table public.leads drop constraint leads_intake_stage_check;
alter table public.leads add constraint leads_intake_stage_check check (intake_stage in ('collecting','complete','name','country','marks','ielts','budget'));
create table public.document_checks (
 id uuid primary key default gen_random_uuid(), lead_id uuid not null references public.leads(id),
 filename text not null, document_type text not null, extracted_fields jsonb not null,
 result text not null check(result in ('OK','Problem')), reasons jsonb not null,
 summary text not null, created_at timestamptz not null default now()
);
create table public.activity_log (
 id uuid primary key default gen_random_uuid(), lead_id uuid references public.leads(id),
 agent_name text not null, action text not null, created_at timestamptz not null default now()
);
create table public.escalations (
 id uuid primary key default gen_random_uuid(), lead_id uuid not null references public.leads(id),
 question text not null, reason text not null, status text not null default 'open' check(status in ('open','resolved')),
 created_at timestamptz not null default now()
);
alter table public.document_checks enable row level security;
alter table public.activity_log enable row level security;
alter table public.escalations enable row level security;
revoke all on public.document_checks, public.activity_log, public.escalations from anon,authenticated;
grant select,insert,update,delete on public.document_checks, public.activity_log, public.escalations to service_role;
create index documents_lead_idx on public.document_checks(lead_id);
create index escalations_lead_idx on public.escalations(lead_id);
create function public.approve_and_deliver(message_id uuid, reviewed_content text, staff_name text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare msg public.messages;
begin
 select * into msg from public.messages where id=message_id for update;
 if not found then raise exception 'Message not found'; end if;
 if msg.status <> 'pending_approval' then return jsonb_build_object('changed',false,'status',msg.status); end if;
 if length(trim(reviewed_content)) not between 1 and 12000 or length(trim(staff_name))=0 then raise exception 'Invalid approval'; end if;
 update public.messages set content=reviewed_content,status='approved',approved_at=now(),approved_by=staff_name where id=message_id;
 update public.messages set status='sent',sent_at=now() where id=message_id;
 insert into public.activity_log(lead_id,agent_name,action) values(msg.lead_id,'Staff','Approved and delivered message '||message_id);
 return jsonb_build_object('changed',true,'status','sent');
end;
$$;
revoke execute on function public.approve_and_deliver(uuid,text,text) from public,anon,authenticated;
grant execute on function public.approve_and_deliver(uuid,text,text) to service_role;
commit;
