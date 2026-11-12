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

## The web build's endpoint client

The web build asks for one whole answer: its request carries no `stream`, which is LAI-F2's choice.
It reads whatever comes, in plain Dart that also runs on the VM:

| File | What it does |
| --- | --- |
| `endpoint_reply.dart` | Reads a reply: the `data:` lines of an event stream, or a body without any as one whole answer. Splits thinking from the answer |
| `endpoint_chat.dart` | The client: the request, the limit, Stop, and the `piece` and `done` events the page takes from the bridge on native builds |
| `web_endpoint.dart` | The browser half only: `fetch`, its abort, and the body's bytes as they arrive |

- **A server's error is shown in its own words.** An `error` in a 200 answer or in a stream line
  ends the answer with its text, whether it is an object with a `message` (OpenAI) or the text
  itself (Ollama). A status outside 200 to 299 fails with `the endpoint answered HTTP <status>:` and
  the first 2000 bytes of the body. An answer without choices, or one that is no JSON, says so and
  shows its start; an empty one says that it is empty.
- **Thinking is not the answer.** `reasoning_content` (llama-server, vLLM) and `reasoning` (Ollama)
  are counted and never shown. So is a `<think>...</think>` block inside the text, also one that
  never closes or whose tag is cut over two chunks, and the white space that follows the block.
  Tags other than `<think>` pass through as text. The rules are those of OxidANT's `answer.rs`,
  which native builds run since the pin of 2026-11-12.
- **A `</think>` without its `<think>`** means the chat template opened the block in the prompt, so
  all text before it was thinking. A whole answer shows none of it. A stream has shown it by then
  and cannot take it back; the answer follows it.
- **A reply without a word is a failure, not an empty bubble**: `the model gave no answer
  (finish_reason length): it spent its budget thinking (412 characters of thinking, 128 tokens);
  set a larger maximum of new tokens or switch thinking off at the endpoint`. A model that only
  thought and ended by itself reads `it only thought (...); switch thinking off at the endpoint`,
  because a larger budget does not help there. Without thinking the message is its first part
  alone. The thinking itself is shown nowhere yet.
- **A silent endpoint fails after 300 s**, OxidANT's limit for a request. Here it runs until the
  first byte and again after each one, and the request is aborted when it passes. A server sends
  a whole answer when the model is done, so for the default request this limits the whole answer.
- **Stop** aborts the request. The answer keeps the text it had and is marked as stopped.

An endpoint that streams without being asked is read piece by piece, and the time to the first
token and the decode rate are then measured as OxidANT measures them. Native builds read replies
in OxidANT, not here. There an answer without words still ends as an empty bubble, because the
bridge's `done` carries no thinking count.

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
error. Native builds hand all three to OxidANT's `text_generate`: its endpoint backend sends the
same three fields, and a local model takes the seed as GenAI's `random_seed`, the schema through
llguidance and the stop strings itself, ending with finish reason `stop`. A local model without
llguidance, such as Windows' GenAI, answers a schema with `json_schema is unsupported on this lane`,
shown above the conversation.

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

`test/endpoint_reply_test.dart` and `test/endpoint_chat_test.dart` run on the VM and in Chrome. The
first reads stream lines, whole answers and `<think>` blocks, also a closing tag alone. The second
drives the client through a fake transport: both reply forms, the three places thinking arrives in,
a reply that was only thinking, a server's errors, both silences, Stop, and a body cut inside a line
or a character. The 300 s limit is tested as a short one; no test waits 300 s.
`test/web_endpoint_test.dart` runs in Chrome only, on a fake `fetch`
(`test/support/fake_fetch.dart`): the request, its abort, the failures above as the page shows
them, and a body read as it arrives. No test talks to a real server.

`test/ai_playground_settings_test.dart` saves settings with a planted API key, reads every byte
under the store's directory and finds no trace of it, then restores the rest in a second controller,
as a restart does. It also covers a broken file, a store that cannot write, the default store through
the mocked support directory, the request body and the three new fields.

`integration_test/text_generate_test.dart` runs on the Linux lanes in the built app, under Xvfb,
against the chain GenAI through OxidANT's bridge. The lane writes the hub's tiny GenAI model
(`tiny-genai-model.py`) and fetches SmolLM2-135M through the hub's `fetch-data-lock.py` from
`third_party/OxidANT/resources/models/llm.lock`, checked by sha256, then passes both directories as
`--dart-define`s. Greedy decoding of `abc` must give exactly `defg`, and SmolLM2-135M's answer to
"What is the capital of France?" must contain `Paris`. A third test points the playground at a
recording loopback server and checks that the request body carries `seed`, `response_format` and
`stop`. An unset model directory fails the test rather than skipping it.
