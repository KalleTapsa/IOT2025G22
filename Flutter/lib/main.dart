import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const PicoApp());
}

class PicoApp extends StatelessWidget {
  const PicoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const PicoHomePage(),
    );
  }
}

class PicoHomePage extends StatefulWidget {
  final http.Client? client;

  const PicoHomePage({super.key, this.client});

  @override
  State<PicoHomePage> createState() => _PicoHomePageState();
}

class _PicoHomePageState extends State<PicoHomePage> {
  late http.Client client;

  @override
  void initState() {
    super.initState();
    client = widget.client ?? http.Client();
  }

  String latestText = "Press the button to get the latest value";
  String historyText = "History will appear here";
  String clearText = "Clear status will appear here";

  bool isLoading = false;
  String? loadingEndpoint;

  final String picoIp = "192.168.1.45"; // Change this to your Pico W's IP address

  Future<void> fetchEndpoint(String endpoint) async {
    final url = Uri.parse("http://$picoIp/$endpoint");

    setState(() {
      isLoading = true;
      loadingEndpoint = endpoint;
      if (endpoint == "latest") {
        latestText = "Loading latest...";
      } else if (endpoint == "history") {
        historyText = "Loading history...";
      } else if (endpoint == "clear") {
        clearText = "Clearing history...";
      }
    });

    try {
      //final response = await http.get(url).timeout(const Duration(seconds: 5));
      final response = await client.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final raw = response.body.trim();

        setState(() {
          if (endpoint == "latest") {
            latestText = formatLatest(raw);
          } else if (endpoint == "history") {
            historyText = "History Results:\n\n$raw";
          } else if (endpoint == "clear") {
            clearText = "History cleared successfully.";
          }
        });
      } else {
        setState(() {
          final error = "HTTP ${response.statusCode}";

          if (endpoint == "latest") latestText = "Latest Error: $error";
          if (endpoint == "history") historyText = "History Error: $error";
          if (endpoint == "clear") clearText = "Clear Error: $error";
        });
      }
    } on TimeoutException {
      setState(() {
        if (endpoint == "latest") latestText = "Latest Error: Request timed out after 5s";
        if (endpoint == "history") historyText = "History Error: Request timed out after 5s";
        if (endpoint == "clear") clearText = "Clear Error: Request timed out after 5s";
      });
    } catch (e) {
      setState(() {
        if (endpoint == "latest") latestText = "Latest Failed: $e";
        if (endpoint == "history") historyText = "History Failed: $e";
        if (endpoint == "clear") clearText = "Clear Failed: $e";
      });
    } finally {
      setState(() {
        isLoading = false;
        loadingEndpoint = null;
      });
    }
  }

  String formatLatest(String raw) {
    final parts = raw.split(",");

    if (parts.length != 4) {
      return "Invalid format: $raw";
    }

    final timestamp = int.tryParse(parts[0]);
    final pressure = double.tryParse(parts[1]);
    final temperature = double.tryParse(parts[2]);
    final humidity = double.tryParse(parts[3]);

    if (timestamp == null || pressure == null || temperature == null || humidity == null) {
      return "Parse error: $raw";
    }

    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true).toLocal();

    return """
Time: ${dt.toString().split('.').first}
Pressure: ${pressure.toStringAsFixed(2)} Pa
Temperature: ${temperature.toStringAsFixed(1)} °C
Humidity: ${humidity.toStringAsFixed(1)} %
""";
  }

    @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pico W Demo App")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // Latest section header with per-request spinner
            Row(
              children: [
                const Text("Latest:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (loadingEndpoint == "latest")
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            Text(latestText),
            const SizedBox(height: 20),

            // History section header with per-request spinner
            Row(
              children: [
                const Text("History:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (loadingEndpoint == "history")
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            Text(historyText),
            const SizedBox(height: 20),

            // Clear section header with per-request spinner
            Row(
              children: [
                const Text("Clear History:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (loadingEndpoint == "clear")
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            Text(clearText),
          ],
        ),
      ),
      floatingActionButton: Wrap(
        spacing: 15,
        children: [
          FloatingActionButton(
            heroTag: "latest",
            onPressed: isLoading ? null : () => fetchEndpoint("latest"),
            tooltip: "Fetch latest",
            child: const Icon(Icons.refresh),
          ),
          FloatingActionButton(
            heroTag: "history",
            onPressed: isLoading ? null : () => fetchEndpoint("history"),
            tooltip: "Fetch history",
            child: const Icon(Icons.list),
          ),
          FloatingActionButton(
            heroTag: "clear",
            onPressed: isLoading ? null : () => fetchEndpoint("clear"),
            backgroundColor: Colors.redAccent,
            tooltip: "Clear history",
            child: const Icon(Icons.delete),
          ),
        ],
      ),
    );
  }
}
