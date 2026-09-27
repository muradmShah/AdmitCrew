-- Apply once after 004_app.sql. Backend-only accounts; no public hash access.
begin;
create table public.student_accounts (
 id uuid primary key default gen_random_uuid(),
 lead_id uuid not null unique references public.leads(id),
 email text not null unique check(email=lower(trim(email))),
 password_hash text not null,
 created_at timestamptz not null default now()
);
alter table public.student_accounts enable row level security;
revoke all on public.student_accounts from anon,authenticated;
grant select,insert,update on public.student_accounts to service_role;
create function public.register_student_account(student_name text, student_email text, student_phone text, encoded_password text, destination text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare student_id uuid;
begin
 insert into public.leads(name,phone_normalized,country,intake_stage,is_test_data)
 values(student_name,student_phone,destination,'marks',false) returning id into student_id;
 insert into public.student_accounts(lead_id,email,password_hash) values(student_id,lower(trim(student_email)),encoded_password);
 insert into public.messages(lead_id,direction,content,agent_name,idempotency_key)
 values(student_id,'outbound','Welcome, '||student_name||'. Your account is ready. What is your percentage of marks?','Intake','welcome:'||student_id);
 insert into public.activity_log(lead_id,agent_name,action) values(student_id,'Intake','Student account created. Welcome reply awaits staff approval.');
 return jsonb_build_object('lead_id',student_id);
end;
$$;
revoke execute on function public.register_student_account(text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.register_student_account(text,text,text,text,text) to service_role;
commit;
