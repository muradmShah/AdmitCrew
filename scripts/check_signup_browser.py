"""Run against the isolated QA server at port 8766, not the user's database."""
from playwright.sync_api import sync_playwright
import uuid

with sync_playwright() as p:
    browser=p.chromium.launch(channel='msedge',headless=True)
    context=browser.new_context(viewport={'width':1440,'height':1000})
    page=context.new_page(); errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto('http://127.0.0.1:8766/student')
    page.wait_for_url('**/#signin')
    page.get_by_role('link',name='Create an account',exact=True).click()
    page.get_by_role('heading',name='Create your account').wait_for()
    page.screenshot(path='output/qa/student-signup-desktop.png',full_page=True)
    page.set_viewport_size({'width':390,'height':844})
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    page.screenshot(path='output/qa/student-signup-mobile.png',full_page=True)
    suffix=uuid.uuid4().hex[:8]
    email='qa-'+suffix+'@example.com'; password='Student-demo-password-123'
    page.get_by_label('Full name',exact=True).fill('QA Student')
    page.get_by_label('Phone number',exact=True).fill('03'+str(int(suffix,16)).zfill(9)[-9:])
    page.get_by_label('Preferred destination').select_option('Canada')
    page.get_by_label('Email address').fill(email)
    page.get_by_label('Password',exact=True).fill(password)
    page.get_by_label('Confirm password',exact=True).fill('does-not-match')
    page.get_by_role('button',name='Create account',exact=False).click()
    page.get_by_role('alert').filter(has_text='passwords do not match').wait_for()
    page.get_by_label('Confirm password',exact=True).fill(password)
    page.get_by_role('button',name='Create account',exact=False).click()
    page.wait_for_url('**/student')
    page.locator('#account-name').filter(has_text='QA Student').wait_for()
    page.get_by_role('button',name='Sign out',exact=True).click()
    page.wait_for_url('**/#signin')
    page.get_by_label('Email address').fill(email)
    page.get_by_label('Password',exact=True).fill('incorrect-password')
    page.get_by_role('button',name='Sign in',exact=False).click()
    page.get_by_role('alert').filter(has_text='Incorrect email or password').wait_for()
    page.get_by_label('Password',exact=True).fill(password)
    page.get_by_role('button',name='Sign in',exact=False).click()
    page.wait_for_url('**/student')
    page.locator('#account-name').filter(has_text='QA Student').wait_for()
    assert not errors,errors
    print('PASS signup, confirmation mismatch, login errors, sign-out, returning login, mobile layout; no JS errors')
    browser.close()
