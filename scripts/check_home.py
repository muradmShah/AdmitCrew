"""Read-only checks for the single-page public website."""
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(channel='msedge', headless=True)
    page = browser.new_page(viewport={'width': 1440, 'height': 1000})
    errors = []
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.goto('http://127.0.0.1:8765/')
    page.locator('.landing-nav').wait_for()
    page.locator('.landing-nav a[href="#about"]').click()
    assert page.url.endswith('/#about')
    assert 'last four decades' in page.locator('#about').inner_text()
    page.locator('.landing-nav a[href="#impact"]').click()
    page.wait_for_timeout(2100)
    assert page.locator('[data-count="100000"]').inner_text() == '100,000'
    assert page.locator('[data-count="40"]').inner_text() == '40'
    page.locator('.landing-signin').click()
    page.get_by_role('heading', name='Sign in to your account').wait_for()
    page.get_by_role('link', name='Create an account', exact=True).click()
    page.get_by_role('heading', name='Create your account').wait_for()
    assert page.url.endswith('/#signup')
    assert page.locator('#student-auth-form').count() == 1
    page.evaluate("document.documentElement.style.scrollBehavior='auto';window.scrollTo(0,0)")
    page.wait_for_timeout(800)
    page.screenshot(path='output/qa/home-desktop.png', full_page=True)
    page.set_viewport_size({'width': 390, 'height': 844})
    page.goto('http://127.0.0.1:8765/')
    page.locator('.landing').wait_for()
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
    page.screenshot(path='output/qa/home-mobile.png', full_page=True)
    page.goto('http://127.0.0.1:8765/staff')
    page.locator('.login-form').wait_for()
    assert not errors, errors
    print('PASS single-page navigation, About, counters, inline authentication forms, mobile width, staff route; no JS errors')
    browser.close()
