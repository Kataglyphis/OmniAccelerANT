function _setCookie(name, value) {
	// NOTE: `expires=2147483647` is not an RFC 7231 HTTP-date (that grammar wants
	// e.g. "Tue, 19 Jan 2038 03:14:07 GMT"), so browsers discard the attribute and
	// this is in fact a SESSION cookie. jotrockenmitlocken's copy carries the same
	// defect; fixing it changes consent-banner lifetime, so it is reported here,
	// not silently changed.
	const expires = "; expires=2147483647"; // ~2038 i.e. until user clears cookies
	// `Secure` (present in jotrockenmitlocken's copy, missing here): SameSite=Strict
	// alone still lets the cookie be written and replayed over plain http, so any
	// downgraded request leaks the consent value. The app is served over https and
	// web/.htaccess sets HSTS, so Secure costs nothing.
	document.cookie = name + "=" + (value || "") + expires + "; SameSite=Strict; Secure";
}

function _getCookie(name) {
	var nameEQ = name + "=";
	var ca = document.cookie.split(';');
	for (var i = 0; i < ca.length; i++) {
		var c = ca[i];
		while (c.charAt(0) == ' ') c = c.substring(1, c.length);
		if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length, c.length);
	}
	return null;
}

function initCookieNotice() {
	const notice = document.getElementById('cookie-notice');
	const consentBtn = document.getElementById('cookie-consent');
	const cookieKey = 'cookie-consent';
	const cookieConsentValue = 'true'
	const activeClass = 'show';
	if (_getCookie(cookieKey) === cookieConsentValue) {
		return;
	}
	notice.classList.add(activeClass);
	consentBtn.classList.add(activeClass);
	consentBtn.addEventListener('click', (e) => {
		e.preventDefault();
		_setCookie(cookieKey, cookieConsentValue);
		notice.classList.remove(activeClass);
		consentBtn.classList.add(activeClass);
	});
}