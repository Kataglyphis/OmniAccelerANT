// Fills the cookie notice and the loading message in the browser's language; a file, so no inline script needs a CSP exception.
(function () {
	function fill() {
		const language = navigator.language || 'en';
		setMessage(language, 'message',
			'Ich verwende ausschließlich technisch notwendige Cookies, um Dienstleistungen zu erbringen.\n'
			+ 'Weitere Informationen finden Sie in der Cookie-Erklärung im unteren Teil der Website. Viel Spaß :)',
			'I only use technically necessary cookies to provide services.\n'
			+ 'Further information can be found in the cookie statement at the bottom of the website. Have fun :)');
		setMessage(language, 'loading-message', 'Noch etwas Geduld ...', 'You will be there soon ...');
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', fill);
	} else {
		fill();
	}
})();
