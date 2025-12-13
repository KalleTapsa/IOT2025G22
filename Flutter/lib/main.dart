import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

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
  Timer? latestTimer;
  Timer? historyTimer;
  List<FlSpot> historyTempSpots = [];
  int? minTs; 
  int? maxTs;
  int? baseEpochSeconds;
  // Parallel arrays to enrich tooltip data
  List<double> historyPressure = [];
  List<double> historyHumidity = [];
  List<int> historyTimestamps = [];
  @override
  void initState() {
    super.initState();
    client = widget.client ?? http.Client();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchEndpoint("latest");
      fetchEndpoint("history");
      
      // Fetch latest every 10 seconds
      latestTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        fetchEndpoint("latest");
      });
      
      // Fetch history every 60 seconds
      historyTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        fetchEndpoint("history");
      });
    });
  }

  @override
  void dispose() {
    latestTimer?.cancel();
    historyTimer?.cancel();
    client.close();
    super.dispose();
  }

  String latestText = "Press the button to get the latest value";
  String historyText = "History will appear here";
  String clearText = "Clear status will appear here";

  bool isLoading = false;
  String? loadingEndpoint;

  final String picoIp = "192.168.1.45"; // Tähän Picon IP-osoite

 Future<void> fetchEndpoint(String endpoint) async {

    final url = Uri.parse("http://$picoIp/$endpoint");

    setState(() {
      isLoading = true;
      loadingEndpoint = endpoint;
      if (endpoint == "latest") latestText = "Loading latest...";
      if (endpoint == "history") historyText = "Loading history...";
      if (endpoint == "clear_history") clearText = "Clearing history...";
    });

    try {
      // Mock data - comment out for real fetch
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (endpoint == "latest") {
        final mockTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final mockResponse = "$mockTimestamp,101325.5,${20 + (DateTime.now().second % 5)}.3,${45 + (DateTime.now().second % 10)}.2";
        setState(() {
          latestText = formatLatest(mockResponse);
        });
        return;
      } else if (endpoint == "history") {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final mockHistory = List.generate(20, (i) {
          final ts = now - (20 - i) * 30;
          final temp = 20 + (i % 5) * 0.5;
          final pressure = 101325 + (i % 3) * 50;
          final humidity = 45 + (i % 8) * 2;
          return "$ts,$pressure,$temp,$humidity";
        }).join("\n");
        setState(() {
          historyText = "";
          _parseHistoryToSpots(mockHistory);
        });
        return;
      } else if (endpoint == "clear_history") {
        setState(() {
          clearText = "History cleared successfully.";
          historyTempSpots = [];
          minTs = null;
          maxTs = null;
        });
        return;
      }
      
      // Real fetch - uncomment to use actual device
      /*
      final response = await client.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final raw = response.body.trim();

        setState(() {
          if (endpoint == "latest") {
            latestText = formatLatest(raw);
          } else if (endpoint == "history") {
            historyText = "";
            _parseHistoryToSpots(raw);
          } else if (endpoint == "clear_history") {
            clearText = "History cleared successfully.";
            historyTempSpots = [];
            minTs = null;
            maxTs = null;
          }
        });
      } else {
        setState(() {
          final error = "HTTP ${response.statusCode}";
          if (endpoint == "latest") latestText = "Latest Error: $error";
          if (endpoint == "history") historyText = "History Error: $error";
          if (endpoint == "clear_history") clearText = "Clear Error: $error";
        });
      }
      */
    } on TimeoutException {
      setState(() {
        if (endpoint == "latest") {
          latestText = "Latest Error: Request timed out.";
        } else if (endpoint == "history") {
          historyText = "History Error: Request timed out.";
        } else if (endpoint == "clear_history") {
          clearText = "Clear Error: Request timed out.";
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request timed out. Check device IP and network.")),
      );
    } catch (e) {
      setState(() {
        if (endpoint == "latest") latestText = "Latest Failed: $e";
        if (endpoint == "history") historyText = "History Failed: $e";
        if (endpoint == "clear_history") clearText = "Clear Failed: $e";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Request failed: $e")),
      );
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

  
   void _parseHistoryToSpots(String raw) {
    final lines = raw.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty);

    final timestamps = <int>[];
    final temps = <double>[];
    final pressures = <double>[];
    final humidities = <double>[];

    for (final line in lines) {
      final parts = line.split(',');
      if (parts.length != 4) continue;

      final ts = int.tryParse(parts[0]);
      final pressure = double.tryParse(parts[1]);
      final temp = double.tryParse(parts[2]);
      final humidity = double.tryParse(parts[3]);

      if (ts != null && temp != null && pressure != null && humidity != null) {
        timestamps.add(ts);
        temps.add(temp);
        pressures.add(pressure);
        humidities.add(humidity);
      }
    }

    if (timestamps.isEmpty) {
      historyTempSpots = [];
      historyPressure = [];
      historyHumidity = [];
      historyTimestamps = [];
      minTs = null;
      maxTs = null;
      baseEpochSeconds = null;
      return;
    }

    final baseTs = timestamps.first;
    baseEpochSeconds = baseTs;

    historyTempSpots = [
      for (int i = 0; i < timestamps.length; i++)
        FlSpot(
          (timestamps[i] - baseTs).toDouble(),
          temps[i],
        ),
    ];
    historyPressure = pressures;
    historyHumidity = humidities;
    historyTimestamps = timestamps;

    minTs = 0;
    maxTs = timestamps.last - baseTs;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pico Weather")),
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
            Image.asset('images/cold.png', width: 150, height: 150),
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
            const SizedBox(height: 12),

            // Temperature history chart
            SizedBox(
              height: 260,
              child: historyTempSpots.isEmpty
                  ? const Center(child: Text("No temperature data yet. Fetch history to see the graph."))
                  : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (maxTs ?? 0).toDouble(),
                        minY: (() {
                          final ys = historyTempSpots.map((s) => s.y);
                          final minY = ys.reduce((a, b) => a < b ? a : b);
                          return (minY - 0.3);
                        })(),
                        maxY: (() {
                          final ys = historyTempSpots.map((s) => s.y);
                          final maxY = ys.reduce((a, b) => a > b ? a : b);
                          return (maxY + 0.3);
                        })(),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          verticalInterval: ((maxTs ?? 0) > 0 ? ((maxTs! / 6).clamp(10, 300)).toDouble() : 60),
                          horizontalInterval: 0.5,
                          getDrawingHorizontalLine: (value) =>
                              FlLine(color: Colors.grey.shade300, strokeWidth: 1),
                          getDrawingVerticalLine: (value) =>
                              FlLine(color: Colors.grey.shade300, strokeWidth: 1),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 0.5,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) =>
                                  Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 11)),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 34,
                              interval: ((maxTs ?? 0) > 0 ? ((maxTs! / 6).toDouble()) : 60),
                              getTitlesWidget: (value, meta) {
                                final seconds = value.toInt();
                                final m = (seconds ~/ 60).toString();
                                final s = (seconds % 60).toString().padLeft(2, '0');
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Text("$m:$s", style: const TextStyle(fontSize: 11)),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: historyTempSpots,
                            isCurved: true,
                            curveSmoothness: 0.2,
                            color: Colors.orange,
                            barWidth: 3,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.orange.withOpacity(0.1),
                            ),
                          ),
                        ],
                        lineTouchData: LineTouchData(
                          handleBuiltInTouches: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (items) => items.map((i) {
                              final idx = i.spotIndex;
                              final seconds = i.x.toInt();
                              final epoch = (baseEpochSeconds ?? 0) + seconds;
                              final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true).toLocal();
                              final timeLabel = "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";
                              final tempStr = i.y.toStringAsFixed(1);
                              String pressureStr = "";
                              String humidityStr = "";
                              if (idx >= 0 && idx < historyPressure.length) {
                                pressureStr = historyPressure[idx].toStringAsFixed(2);
                              }
                              if (idx >= 0 && idx < historyHumidity.length) {
                                humidityStr = historyHumidity[idx].toStringAsFixed(1);
                              }
                              return LineTooltipItem(
                                "$timeLabel\n$tempStr °C\n$pressureStr hPa\n$humidityStr %RH",
                                const TextStyle(color: Colors.white),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
            ),

            // Clear section header with per-request spinner
            Row(
              children: [
                const Text("Clear History:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (loadingEndpoint == "clear_history")
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
            heroTag: "clear_history",
            onPressed: isLoading ? null : () => fetchEndpoint("clear_history"),
            backgroundColor: Colors.redAccent,
            tooltip: "Clear",
            child: const Icon(Icons.delete),
          ),
        ],
      ),
    );
  }
}
