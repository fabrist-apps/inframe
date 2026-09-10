#!/usr/bin/env python3

import argparse
import time

from selenium import webdriver
from selenium.webdriver.support.ui import WebDriverWait


def create_driver(browser: str):
    if browser == 'chrome':
        options = webdriver.ChromeOptions()
        options.add_argument('--headless=new')
        options.add_argument('--no-sandbox')
        options.add_argument('--disable-dev-shm-usage')
        driver = webdriver.Chrome(options=options)
        driver.execute_cdp_cmd('Performance.enable', {})
        return driver
    if browser == 'firefox':
        options = webdriver.FirefoxOptions()
        options.add_argument('-headless')
        return webdriver.Firefox(options=options)
    if browser == 'safari':
        return webdriver.Safari()
    raise ValueError(f'Unsupported browser: {browser}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('browser', choices=('chrome', 'firefox', 'safari'))
    parser.add_argument('--url', default='http://localhost:8080')
    arguments = parser.parse_args()

    driver = create_driver(arguments.browser)
    try:
        driver.get(arguments.url)
        WebDriverWait(driver, 240).until(
            lambda active: active.find_element('tag name', 'body').text.startswith(('PASS', 'FAIL'))
        )
        body = driver.find_element('tag name', 'body').text
        if body.startswith('FAIL'):
            raise RuntimeError(body)
        user_agent = driver.execute_script('return navigator.userAgent')
        isolated = driver.execute_script('return window.crossOriginIsolated')
        if not isolated:
            raise RuntimeError('The verification page is not cross-origin isolated.')
        print(f'TURSO_WEB_RUNTIME browser={arguments.browser} user_agent={user_agent}')
        if arguments.browser == 'chrome':
            metrics = driver.execute_cdp_cmd('Performance.getMetrics', {})['metrics']
            values = {metric['name']: metric['value'] for metric in metrics}
            print(
                'TURSO_WEB_MEMORY rows=2000 '
                f"js_heap_used={int(values.get('JSHeapUsedSize', 0))} "
                f"js_heap_total={int(values.get('JSHeapTotalSize', 0))}"
            )
        time.sleep(1)
    finally:
        driver.quit()


if __name__ == '__main__':
    main()
