{{flutter_js}}
{{flutter_build_config}}

// Emoji and symbol fallback fonts come from this site, including when the engine is already local.
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  config: {
    fontFallbackBaseUrl: "fallback-fonts/",
  },
});
