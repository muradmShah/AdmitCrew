"""One storage contract, with explicit local-demo and Supabase implementations."""
import datetime as dt
import json
import os
from pathlib import Path
import sqlite3
import threading
import uuid

ROOT = Path(__file__).parent
TABLES = ('programs', 'leads', 'messages', 'document_checks', 'activity_log', 'escalations')
STORAGE_TABLES = TABLES + ('student_accounts',)
def now(): return dt.datetime.now(dt.timezone.utc).isoformat()

class Repository:
    def __init__(self, local_path=None):
        self.lock = threading.RLock()
        self.client = None
        url, key = os.getenv('SUPABASE_URL',''), os.getenv('SUPABASE_SECRET_KEY','')
        self.remote = local_path is None and bool(url and key and 'YOUR_' not in url and 'YOUR_' not in key)
        if self.remote:
            from supabase import create_client
            self.client = create_client(url,key)
            # Never silently fall back to another database on a connection error.
            for table in STORAGE_TABLES: self.client.table(table).select('id').limit(1).execute()
        else:
            path=Path(local_path or ROOT/'data'/'admitcrew-v2.db')
            path.parent.mkdir(parents=True,exist_ok=True)
            self.db=sqlite3.connect(path,check_same_thread=False)
            for t in STORAGE_TABLES:
                self.db.execute(f'CREATE TABLE IF NOT EXISTS {t} (id TEXT PRIMARY KEY, payload TEXT NOT NULL)')
            self.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS lead_phone ON leads(json_extract(payload,'$.phone_normalized'))")
            self.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS draft_key ON messages(json_extract(payload,'$.idempotency_key'))")
            self.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS account_email ON student_accounts(json_extract(payload,'$.email'))")
            self.db.execute("CREATE UNIQUE INDEX IF NOT EXISTS account_lead ON student_accounts(json_extract(payload,'$.lead_id'))")
            self.db.commit()
            self.seed()

    def all(self,table,**filters):
        if table not in STORAGE_TABLES: raise ValueError('Invalid table')
        with self.lock:
            if self.remote:
                query=self.client.table(table).select('*').order('created_at')
                for key,value in filters.items(): query=query.eq(key,value)
                rows=[]; start=0
                while True:
                    page=query.range(start,start+999).execute().data
                    rows.extend(page)
                    if len(page)<1000: return rows
                    start+=1000
            rows=[json.loads(r[0]) for r in self.db.execute(f'SELECT payload FROM {table} ORDER BY rowid')]
            return [r for r in rows if all(r.get(k)==v for k,v in filters.items())]

    def one(self,table,**filters):
        rows=self.all(table,**filters)
        return rows[0] if rows else None

    def add(self,table,data):
        with self.lock:
            row={'id':str(uuid.uuid4()),'created_at':now(),**data}
            if self.remote: return self.client.table(table).insert(row).execute().data[0]
            self.db.execute(f'INSERT INTO {table}(id,payload) VALUES(?,?)',(row['id'],json.dumps(row)))
            self.db.commit()
            return row

    def update(self,table,ident,changes):
        with self.lock:
            if self.remote:
                rows=self.client.table(table).update(changes).eq('id',ident).execute().data
                if not rows: raise ValueError('Record not found')
                return rows[0]
            row=self.one(table,id=ident)
            if not row: raise ValueError('Record not found')
            row.update(changes)
            self.db.execute(f'UPDATE {table} SET payload=? WHERE id=?',(json.dumps(row),ident)); self.db.commit()
            return row

    def log(self,agent,action,lead_id=None):
        return self.add('activity_log',{'agent_name':agent,'action':action,'lead_id':lead_id})

    def register_student(self,name,email,phone,password_hash,country):
        if self.remote:
            try:
                return self.client.rpc('register_student_account',{'student_name':name,'student_email':email,
                    'student_phone':phone,'encoded_password':password_hash,'destination':country}).execute().data
            except Exception as exc:
                if getattr(exc,'code',None)=='23505': raise ValueError('An account or profile already exists for these details. Sign in, or contact staff.')
                raise
        with self.lock:
            if self.one('student_accounts',email=email) or self.one('leads',phone_normalized=phone):
                raise ValueError('An account or profile already exists for these details. Sign in, or contact staff.')
            lead={'id':str(uuid.uuid4()),'created_at':now(),'name':name,'phone_normalized':phone,'country':country,
                'marks':None,'ielts':None,'budget':None,'last_reply_at':now(),'intake_stage':'marks','is_test_data':False}
            account={'id':str(uuid.uuid4()),'created_at':now(),'lead_id':lead['id'],'email':email,'password_hash':password_hash}
            draft={'id':str(uuid.uuid4()),'created_at':now(),'lead_id':lead['id'],'direction':'outbound',
                'content':f"Welcome, {name}. Your account is ready. What is your percentage of marks?",'agent_name':'Intake',
                'status':'pending_approval','idempotency_key':'welcome:'+lead['id'],'approved_at':None,'approved_by':None,'sent_at':None}
            event={'id':str(uuid.uuid4()),'created_at':now(),'lead_id':lead['id'],'agent_name':'Intake','action':'Student account created. Welcome reply awaits staff approval.'}
            with self.db:
                for table,row in [('leads',lead),('student_accounts',account),('messages',draft),('activity_log',event)]:
                    self.db.execute(f'INSERT INTO {table}(id,payload) VALUES(?,?)',(row['id'],json.dumps(row)))
            return {'lead_id':lead['id']}

    def draft(self,lead_id,content,agent,key=None):
        with self.lock:
            if key:
                old=self.one('messages',idempotency_key=key)
                if old: return old
            return self.add('messages',{'lead_id':lead_id,'direction':'outbound','content':content,'agent_name':agent,
                'status':'pending_approval','idempotency_key':key,'approved_at':None,'approved_by':None,'sent_at':None})

    def approve(self,ident,content,staff):
        if self.remote:
            return self.client.rpc('approve_and_deliver',{'message_id':ident,'reviewed_content':content,'staff_name':staff}).execute().data
        with self.lock:
            row=self.one('messages',id=ident)
            if not row: raise ValueError('Message not found')
            if row['status']!='pending_approval': return {'changed':False,'status':row['status']}
            if not content.strip(): raise ValueError('Message is empty')
            # The messages table IS the simulated inbox. Delivery and approval are one atomic transaction.
            row.update(content=content,approved_by=staff,approved_at=now(),sent_at=now(),status='sent')
            event={'id':str(uuid.uuid4()),'created_at':now(),'agent_name':'Staff','action':'Approved and delivered message '+ident,'lead_id':row['lead_id']}
            with self.db:
                self.db.execute('UPDATE messages SET payload=? WHERE id=?',(json.dumps(row),ident))
                self.db.execute('INSERT INTO activity_log VALUES(?,?)',(event['id'],json.dumps(event)))
            return {'changed':True,'status':'sent'}

    def seed(self):
        if not self.all('programs'):
            for u,c,p,f,d,m,i,docs in json.loads((ROOT/'programs.json').read_text(encoding='utf-8')):
                self.add('programs',dict(university=u,country=c,program=p,fee_display=f,deadline=d,min_marks=m,min_ielts=i,required_documents=docs.split(', '),is_practice_data=True))
        if not self.all('leads'):
            for name,phone,country,marks,ielts,days in [('Ali Khan','923012345678','UK',78,6.5,0),('Ayesha Noor','923339876543','Canada',85,7,0),('Hamza Iqbal','923462223344','UK',69,None,4)]:
                self.add('leads',dict(name=name,phone_normalized=phone,country=country,marks=marks,ielts=ielts,budget=None,intake_stage='complete',is_test_data=True,last_reply_at=(dt.datetime.now(dt.timezone.utc)-dt.timedelta(days=days)).isoformat()))
            self.log('Coordinator','Practice workspace initialized with 15 programs and three students.')
