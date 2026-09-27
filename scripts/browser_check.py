"""Browser QA against the running local app; creates fictional demonstration activity."""
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'output'/'qa';out.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
    browser=p.chromium.launch(channel='msedge',headless=True)
    context=browser.new_context(viewport={'width':1440,'height':1050})
    page=context.new_page();errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto('http://127.0.0.1:8765/staff')
    page.get_by_label('Staff password').fill('admitcrew-demo')
    page.get_by_role('button',name='Open workspace').click()
    page.get_by_role('heading',name='AdmitCrew.',exact=True).wait_for()
    page.screenshot(path=str(out/'dashboard.png'),full_page=True)
    for tab in ['Students','Program catalog','Documents','Activity','Demo guide','Approval inbox']:
        page.locator(f'nav button[data-page="{tab}"]').click()
        page.wait_for_timeout(100)
    student=context.new_page();student.on('pageerror',lambda e:errors.append(str(e)))
    context.request.post('http://127.0.0.1:8765/api/student/start',data={'phone':'03012345678'})
    student.goto('http://127.0.0.1:8765/student')
    student.locator('#chat-name').filter(has_text='Ali Khan').wait_for()
    student.get_by_label('Your message').fill('What are the fees and requirements at Manchester?')
    student.get_by_role('button',name='Send',exact=False).click()
    student.locator('#waiting').filter(has_text='waiting for staff').wait_for()
    assert student.locator('#chat-history').get_by_text('£32,000',exact=False).count()==0
    page.reload()
    page.get_by_role('heading',name='AdmitCrew.',exact=True).wait_for()
    page.locator('nav button[data-page="Approval inbox"]').click()
    page.get_by_role('button',name='Approve & deliver').first.click()
    student.get_by_text('Fee per year: £32,000',exact=False).wait_for(timeout=15000)
    student.locator('#document').set_input_files(str(ROOT/'output/pdf/passport-b.pdf'))
    student.get_by_role('status').filter(has_text='Document checked').wait_for()
    page.reload();page.locator('nav button[data-page="Documents"]').click()
    page.get_by_role('cell',name='Expired',exact=True).wait_for()
    page.screenshot(path=str(out/'documents.png'),full_page=True)
    student.screenshot(path=str(out/'student.png'),full_page=True)
    page.set_viewport_size({'width':390,'height':844})
    page.locator('nav button[data-page="Overview"]').click()
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Mobile overflow'
    page.screenshot(path=str(out/'mobile.png'),full_page=True)
    assert not errors,errors
    print('PASS browser: login, navigation, student chat, approval visibility, PDF upload, mobile layout; zero JS errors')
    browser.close()
