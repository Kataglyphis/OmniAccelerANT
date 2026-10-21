// Sets an element's text to the German or the English message by the browser's language.
function setMessage(language, elementId, messageDe, messageEn) {
	const element = document.getElementById(elementId);
	if (!element) {
		return;
	}
	element.textContent = language.substring(0, 2) === 'de' ? messageDe : messageEn;
}
