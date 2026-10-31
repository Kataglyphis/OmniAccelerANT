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
option is offered only where `text_local_available` loads the chain GenAI. The settings live for the
running app and are not saved yet.

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
