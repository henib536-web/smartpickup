class Env {
  // Vous ne changez l'adresse QUE ICI une seule fois
  static const String baseUrl = "https://rubber-zips-atrocious.ngrok-free.dev";

  static const String mapboxToken = "YOUR_MAPBOX_TOKEN";

  // Ngrok free sometimes injects a browser warning page that breaks XHR/CORS.
  // This header bypasses it for API calls.
  static const Map<String, String> defaultHeaders = {
    "ngrok-skip-browser-warning": "true",
    "Content-Type": "application/json",
  };
}
