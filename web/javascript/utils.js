// Function to set message based on language
function setMessage(language, messageDivContainerName, messageDe, messageEn) {

	var messageElement = document.getElementById(messageDivContainerName);

	// Check if the element exists
	if (!messageElement) {
		return;
	}
	var message = "";

	switch (language) {
		case "de":
			message=messageDe
			break;
		case "en":
			message = messageEn;
			break;
		// Add more cases for other languages as needed
		default:
			message = messageEn;
	}

	// Set the message content
	messageElement.textContent = message;
}