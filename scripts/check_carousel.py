"""Read-only browser verification of destination motion and navigation."""
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser=p.chromium.launch(channel='msedge',headless=True)
    context=browser.new_context(viewport={'width':1440,'height':1000})
    page=context.new_page();errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.goto('http://127.0.0.1:8765/student/signup')
    root=page.locator('.opportunities');root.scroll_into_view_if_needed()
    page.get_by_role('button',name='Next destination').click()
    page.wait_for_timeout(750)
    assert page.locator('.destination-slide.is-current').get_attribute('data-slide')=='1'
    page.get_by_role('button',name='Show Germany',exact=True).click()
    page.wait_for_timeout(750)
    page.locator('.destination-stage').focus();page.keyboard.press('ArrowRight');page.wait_for_timeout(750)
    assert page.locator('.destination-slide.is-current').get_attribute('data-slide')=='3'
    page.get_by_role('button',name='Pause slideshow').click()
    assert page.get_by_role('button',name='Play slideshow').is_visible()
    page.screenshot(path='output/qa/opportunities-desktop.png')
    page.get_by_role('button',name='Show Germany',exact=True).click();page.wait_for_timeout(750)
    page.get_by_role('link',name='Explore Germany').click()
    assert page.locator('#student-country').input_value()=='Germany'
    page.set_viewport_size({'width':390,'height':844});root.scroll_into_view_if_needed()
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    page.screenshot(path='output/qa/opportunities-mobile.png')
    reduced=browser.new_context(reduced_motion='reduce');r=reduced.new_page()
    r.goto('http://127.0.0.1:8765/student/signup');r.locator('.opportunities').scroll_into_view_if_needed()
    assert r.get_by_role('button',name='Play slideshow').is_visible()
    r.wait_for_timeout(6800)
    assert r.locator('.destination-slide.is-current').get_attribute('data-slide')=='0'
    r.get_by_role('button',name='Next destination').click();r.wait_for_timeout(100)
    assert r.locator('.destination-slide.is-current').get_attribute('data-slide')=='1'
    assert not errors,errors
    print('PASS carousel controls, keyboard, pause, destination sign-up selection, mobile, reduced motion; no JS errors')
    browser.close()
