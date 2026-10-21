// Shows the consent notice until its button sets a technically necessary cookie.
(function () {
	// Max-Age, since an unparsable Expires made it a session cookie; 400 days is the browsers' cap; path=/ spans the site.
	const CONSENT_MAX_AGE_SECONDS = 400 * 24 * 60 * 60;
	const COOKIE_KEY = 'cookie-consent';
	const COOKIE_VALUE = 'true';

	function setCookie(name, value) {
		// Secure on https only: a plain-http LAN page drops a Secure cookie, and the notice came back on every visit.
		const secure = location.protocol === 'https:' ? '; Secure' : '';
		document.cookie = name + '=' + value + '; Max-Age=' + CONSENT_MAX_AGE_SECONDS + '; path=/; SameSite=Strict' + secure;
	}

	function getCookie(name) {
		const prefix = name + '=';
		for (const part of document.cookie.split(';')) {
			const cookie = part.trim();
			if (cookie.indexOf(prefix) === 0) {
				return cookie.substring(prefix.length);
			}
		}
		return null;
	}

	function initCookieNotice() {
		const notice = document.getElementById('cookie-notice');
		const consentButton = document.getElementById('cookie-consent');
		if (!notice || !consentButton || getCookie(COOKIE_KEY) === COOKIE_VALUE) {
			return;
		}
		notice.classList.add('show');
		consentButton.addEventListener('click', function (event) {
			event.preventDefault();
			setCookie(COOKIE_KEY, COOKIE_VALUE);
			notice.classList.remove('show');
		});
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', initCookieNotice);
	} else {
		initCookieNotice();
	}
})();
