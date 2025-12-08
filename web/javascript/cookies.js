function _setCookie(name, value) {
	const expires = "; expires=2147483647"; // ~2038 i.e. until user clears cookies
	document.cookie = name + "=" + (value || "") + expires + "; SameSite=Strict";
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