# AI Playground

The AI Playground page (`/aiPlayground`, `lib/Pages/AiPlaygroundPage/`) chats with a language model
and shows how fast it answers. It is LAI-F1 and LAI-F2 of
[ANTfrastructure's language-AI plan](https://github.com/Kataglyphis/ANTfrastructure/blob/develop/docs/language-ai.md),
built from [ANThology's chat widgets](https://github.com/Kataglyphis/ANThology/blob/develop/docs/chat-widgets.md)
and [OxidANT's text bridge](https://github.com/Kataglyphis/OxidANT/blob/develop/docs/text.md).

## Where the answers come from

| Source | Platforms | How |
| --- | --- | --- |
| Endpoint | every platform | An OpenAI-compatible server by base URL, model and optional API key. The default is `http://127.0.0.1:18200` with `smollm2_135m_instruct-cpu`, OrchestrANT's `orchestrant-serve` on ModelANT's SmolLM2 |
| Local model | Linux, Windows | A GenAI model directory, run in the app's process on the chain's ONNX Runtime GenAI with the CPU, CUDA or DirectML provider |

Native builds go through OxidANT's `text_generate`, which streams each piece as it is decoded. The
web build has no such bridge, so it fetches one whole answer from the endpoint and shows it at once;
there the decode rate stays 0 and the time to the first token is the request's whole time. The local
option is offered only where `text_local_available` loads the chain GenAI.

## Saved settings

Every change is saved at once and restored at the next start: a JSON file,
`ai_playground_settings.json`, in the app's support directory on native builds, and the browser's
local storage on the web (`playground_settings_store.dart`). **The API key is never written.**
`PlaygroundSettings.toJson` leaves it out, every store writes only that encoding, and the key lives
in memory until the app closes. A file that cannot be read shows its error above the conversation
and the defaults apply.

## Seed, JSON schema and stop strings

Under the temperature the form takes a seed (empty draws a fresh answer each time), a JSON schema
the answer must follow (empty for free text) and stop strings, one per line. The web build sends
them as OpenAI's `seed`, `response_format` (`{"type": "json_schema", "json_schema": {"name":
"response", "schema": ..., "strict": true}}`) and `stop` (`endpoint_request.dart`); a field left
empty is left out of the request. A schema that is not a JSON object fails the request with its
error. Native builds do not pass them yet: the pinned OxidANT's `TextOptions` has no such fields.

## Using it

Each message is sent with the system prompt and the whole conversation before it. While an answer
runs, the button stops it after its current token, and the answer is marked as stopped. Under each
finished answer the page shows the token count, the time to the first token and the decode rate. A
failure, such as an unreachable endpoint or a missing model, appears above the conversation.
"New conversation" clears it.

## Tests

`test/ai_playground_test.dart` drives the controller and the view with a fake backend: streaming,
the figures, the conversation history, waiting and stopping, and a failure. It also checks that the
bridge client hands the settings to a mocked Rust core.

`test/ai_playground_settings_test.dart` saves settings with a planted API key, reads every byte
under the store's directory and finds no trace of it, then restores the rest in a second controller,
as a restart does. It also covers a broken file, a store that cannot write, the default store through
the mocked support directory, the request body and the three new fields.
