"""Run with python app.py. Loopback-only educational admissions workspace."""
import os
from pathlib import Path
import secrets
import threading
import time
from dotenv import load_dotenv
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from repository import Repository, TABLES
from agents import Coordinator
from student_auth import email_address, hash_password, verify_password, DUMMY_HASH

ROOT=Path(__file__).parent
load_dotenv(ROOT/'.env')
app=FastAPI(title='AdmitCrew',docs_url=None,redoc_url=None)
repo=None; coordinator=None; startup_error=None
try:
    repo=Repository(); coordinator=Coordinator(repo)
except Exception:
    startup_error='Supabase connection failed. Check .env and run migrations 001, 002, 004, and 005. No local fallback was used.'
sessions={}; login_attempts={}
staff_password=os.getenv('STAFF_PASSWORD') or 'admitcrew-demo'
staff_email=email_address(os.getenv('STAFF_EMAIL') or 'admin@admitcrew.local')
if repo and repo.remote and staff_password=='admitcrew-demo':
    startup_error='Set a private STAFF_PASSWORD in .env before using Supabase.'

@app.middleware('http')
async def request_guard(request,call_next):
    if request.method=='POST':
        origin=request.headers.get('origin')
        if origin and origin!=str(request.base_url).rstrip('/'):
            return JSONResponse({'detail':'Cross-origin request blocked'},status_code=403)
        if int(request.headers.get('content-length','0'))>3_000_000:
            return JSONResponse({'detail':'Upload is too large'},status_code=413)
    response=await call_next(request)
    response.headers['X-Content-Type-Options']='nosniff'
    response.headers['Cache-Control']='no-store'
    response.headers['Content-Security-Policy']="default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; frame-ancestors 'none'"
    return response

@app.exception_handler(ValueError)
async def bad_input(request,exc): return JSONResponse({'detail':str(exc)},status_code=400)

@app.exception_handler(Exception)
async def unexpected(request,exc):
    return JSONResponse({'detail':'Operation failed. Check database connectivity and retry. No automatic message was sent.'},status_code=503)

def ready():
    if startup_error or repo is None: raise HTTPException(503,startup_error or 'Database unavailable')

def identity(request,role):
    ready()
    entry=sessions.get(request.cookies.get('admitcrew_'+role,''))
    if not entry or entry.get('role')!=role or entry['expires']<time.time(): raise HTTPException(401,'Please sign in again.')
    return entry

def set_session(response,role,**data):
    token=secrets.token_urlsafe(32)
    sessions[token]={'expires':time.time()+28800,'role':role,**data}
    response.set_cookie('admitcrew_'+role,token,httponly=True,samesite='strict',max_age=28800)

class Login(BaseModel): password:str=Field(max_length=200)
class Start(BaseModel): phone:str=Field(min_length=5,max_length=40)
class StudentLogin(BaseModel):
    email:str=Field(min_length=3,max_length=254)
    password:str=Field(min_length=1,max_length=128)
class Signup(StudentLogin):
    name:str=Field(min_length=2,max_length=100)
    phone:str=Field(min_length=5,max_length=40)
    country:str=Field(max_length=50)
class Chat(BaseModel): text:str=Field(min_length=1,max_length=4000); request_id:str=Field(min_length=8,max_length=100)
class Approval(BaseModel): content:str=Field(min_length=1,max_length=12000)
class Upload(BaseModel): filename:str=Field(min_length=1,max_length=150); content:str=Field(max_length=2800000)

@app.get('/api/health')
def health():
    return {'ready':not startup_error,'error':startup_error,'storage':'Supabase' if repo and repo.remote else 'Local SQLite demo',
        'ai':'OpenAI intent routing' if os.getenv('OPENAI_API_KEY') else 'Rule-based demo',
        'demo_password':'admitcrew-demo' if staff_password=='admitcrew-demo' and not (repo and repo.remote) else None,'delivery':'Simulated student inbox'}

@app.post('/api/login')
def login(body:Login,request:Request):
    ready()
    ip=request.client.host; recent=[t for t in login_attempts.get(ip,[]) if time.time()-t<60]
    if len(recent)>=10: raise HTTPException(429,'Too many attempts. Wait one minute.')
    if not secrets.compare_digest(body.password,staff_password):
        login_attempts[ip]=recent+[time.time()]; raise HTTPException(401,'Incorrect staff password.')
    response=JSONResponse({'ok':True}); set_session(response,'staff',name='Office staff'); return response

@app.post('/api/logout')
def logout(request:Request):
    sessions.pop(request.cookies.get('admitcrew_staff',''),None)
    response=JSONResponse({'ok':True}); response.delete_cookie('admitcrew_staff'); return response

@app.get('/api/state')
def state(request:Request):
    identity(request,'staff')
    return {t:repo.all(t) for t in TABLES}

@app.post('/api/student/start')
def start(body:Start,request:Request):
    identity(request,'staff')
    from agents import normalize_phone
    existing=repo.one('leads',phone_normalized=normalize_phone(body.phone))
    if not existing or not existing.get('is_test_data'): raise HTTPException(403,'Staff demo access is limited to existing fictional profiles.')
    response=JSONResponse({'existing':True,'lead_id':existing['id']})
    set_session(response,'student',lead_id=existing['id']); return response

def student_rate_limit(request):
    key='student:'+request.client.host
    recent=[t for t in login_attempts.get(key,[]) if time.time()-t<60]
    if len(recent)>=10: raise HTTPException(429,'Too many attempts. Please wait one minute.')
    login_attempts[key]=recent+[time.time()]

@app.post('/api/student/signup')
def signup(body:Signup,request:Request):
    ready();student_rate_limit(request)
    from agents import normalize_phone
    name=' '.join(body.name.split())
    if len(name)<2: raise ValueError('Enter your full name.')
    if body.country not in ('UK','Canada','Germany','Australia'): raise ValueError('Choose one of the available destinations.')
    if email_address(body.email)==staff_email: raise ValueError('This email is reserved. Use your student email address.')
    account=repo.register_student(name,email_address(body.email),normalize_phone(body.phone),hash_password(body.password),body.country)
    response=JSONResponse({'ok':True},status_code=201)
    sessions.pop(request.cookies.get('admitcrew_student',''),None)
    set_session(response,'student',lead_id=account['lead_id']);return response

@app.post('/api/student/login')
def student_login(body:StudentLogin,request:Request):
    ready();student_rate_limit(request)
    account=repo.one('student_accounts',email=email_address(body.email))
    valid=verify_password(body.password,account['password_hash'] if account else DUMMY_HASH)
    if not account or not valid: raise HTTPException(401,'Incorrect email or password.')
    sessions.pop(request.cookies.get('admitcrew_student',''),None)
    response=JSONResponse({'ok':True});set_session(response,'student',lead_id=account['lead_id']);return response

@app.post('/api/account/login')
def account_login(body:StudentLogin,request:Request):
    ready()
    if email_address(body.email)==staff_email:
        student_rate_limit(request)
        if not secrets.compare_digest(body.password.encode(),staff_password.encode()):
            raise HTTPException(401,'Incorrect email or password.')
        sessions.pop(request.cookies.get('admitcrew_staff',''),None)
        response=JSONResponse({'ok':True,'role':'staff','redirect':'/staff'})
        set_session(response,'staff',name='Office staff');return response
    response=student_login(body,request)
    # Student endpoint issues only a student session; role is never client-controlled.
    return response

@app.post('/api/student/logout')
def student_logout(request:Request):
    sessions.pop(request.cookies.get('admitcrew_student',''),None)
    response=JSONResponse({'ok':True});response.delete_cookie('admitcrew_student');return response

@app.get('/api/student')
def student(request:Request):
    user=identity(request,'student'); ident=user['lead_id']
    messages=repo.all('messages',lead_id=ident)
    return {'lead':repo.one('leads',id=ident),'messages':[m for m in messages if m['status'] in ('received','sent')],
        'waiting':sum(m['status']=='pending_approval' for m in messages)}

@app.post('/api/student/chat')
def chat(body:Chat,request:Request):
    user=identity(request,'student'); lead=repo.one('leads',id=user['lead_id'])
    if not body.text.strip(): raise ValueError('Write a message first.')
    coordinator.chat(lead,body.text.strip(),lead['id']+':'+body.request_id)
    return {'status':'pending_approval'}

@app.post('/api/student/document')
def document(body:Upload,request:Request):
    user=identity(request,'student'); lead=repo.one('leads',id=user['lead_id'])
    coordinator.document(lead,body.filename,body.content)
    return {'status':'pending_approval'}

@app.post('/api/approve/{ident}')
def approve(ident:str,body:Approval,request:Request):
    staff=identity(request,'staff')
    return repo.approve(ident,body.content.strip(),staff['name'])

@app.post('/api/reject/{ident}')
def reject(ident:str,request:Request):
    identity(request,'staff')
    with repo.lock:
        row=repo.one('messages',id=ident)
        if not row: raise ValueError('Message not found')
        if row['status']=='pending_approval':
            repo.update('messages',ident,{'status':'rejected'}); repo.log('Staff','Draft rejected.',row['lead_id'])
    return {'ok':True}

@app.post('/api/reminders')
def reminders(request:Request):
    identity(request,'staff'); return {'count':coordinator.reminders()}

@app.post('/api/escalations/{ident}')
def resolve(ident:str,body:Approval,request:Request):
    identity(request,'staff')
    if not body.content.strip(): raise ValueError('Write a staff response first.')
    with repo.lock:
        row=repo.one('escalations',id=ident)
        if not row: raise ValueError('Staff request not found')
        if row['status']=='open':
            repo.draft(row['lead_id'],body.content,'Staff','escalation:'+ident)
            repo.update('escalations',ident,{'status':'resolved'})
            repo.log('Staff','Escalation response queued for approval.',row['lead_id'])
    return {'ok':True}

@app.get('/samples/{filename}')
def sample(filename:str):
    if filename not in ('passport-a.pdf','passport-b.pdf','transcript.pdf','ielts.pdf'): raise HTTPException(404)
    return FileResponse(ROOT/'output'/'pdf'/filename,filename=filename)

@app.get('/')
@app.get('/staff')
@app.get('/student')
@app.get('/student/signup')
@app.get('/student/login')
def page(): return FileResponse(ROOT/'static'/'index.html')
app.mount('/static',StaticFiles(directory=ROOT/'static'),name='static')

def reminder_loop():
    while True:
        time.sleep(3600)
        if coordinator:
            try: coordinator.reminders()
            except Exception: pass

if __name__=='__main__':
    import uvicorn
    if os.getenv('AUTO_REMINDERS')=='true': threading.Thread(target=reminder_loop,daemon=True).start()
    uvicorn.run(app,host='127.0.0.1',port=int(os.getenv('PORT','8765')))
