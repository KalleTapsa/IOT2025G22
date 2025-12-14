import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

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
  List<double> historyPressure = [];
  List<double> historyHumidity = [];
  List<int> historyTimestamps = [];
  
  String currentImage = 'images/warm.png';
  
  @override
  void initState() {
    super.initState();
    client = widget.client ?? http.Client();
    ipController.text = picoIp;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isIpSet) return; // Don't fetch until user sets IP
      
      fetchEndpoint("latest");
      fetchEndpoint("history");
      
      // Fetch latest every 15 seconds
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
    ipController.dispose();
    client.close();
    super.dispose();
  }

  String latestText = "";
  String historyText = "History will appear here";
  String clearText = "Clear status will appear here";

  bool isLoading = false;
  String? loadingEndpoint;
  bool isIpSet = false;

  String picoIp = "192.168.1.45"; // Picon IP-osoite
  final TextEditingController ipController = TextEditingController();

 Future<void> fetchEndpoint(String endpoint) async {

    final url = Uri.parse("http://$picoIp/$endpoint");

    setState(() {
      isLoading = true;
      loadingEndpoint = endpoint;
      if (endpoint == "latest") {
        latestText = "Loading latest...";
        currentImage = '';
      }
      if (endpoint == "history") historyText = "Loading history...";
      if (endpoint == "clear_history") clearText = "Clearing history...";
    });

    try {
      final response = await client.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final raw = response.body.trim();

        setState(() {
          if (endpoint == "latest") {
            latestText = formatLatest(raw);
            final parts = raw.split(",");
            if (parts.length == 4) {
              final temp = double.tryParse(parts[2]);
              final humidity = double.tryParse(parts[3]);
              if (temp != null && humidity != null) {
                currentImage = _getImageForConditions(temp, humidity);
              }
            }
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
          if (endpoint == "latest") {
            latestText = "Latest Error: $error";
            // Restore image instead of showing loader
            if (currentImage.isEmpty) currentImage = 'images/cold.png';
          }
          if (endpoint == "history") historyText = "History Error: $error";
          if (endpoint == "clear_history") clearText = "Clear Error: $error";
        });
      }
    } on TimeoutException {
      setState(() {
        if (endpoint == "latest") {
          latestText = "Latest Error: Request timed out.";
          // Restore image instead of showing loader
          if (currentImage.isEmpty) currentImage = 'images/warm.png';
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
        if (endpoint == "latest") {
          latestText = "Latest Failed: $e";
          // Restore image instead of showing loader
          if (currentImage.isEmpty) currentImage = 'images/warm.png';
        }
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

    final formatted = DateFormat('HH:mm:ss dd:MM:yyyy').format(dt);

    return """
      Time: $formatted
      Temperature: ${temperature.toStringAsFixed(1)} °C
      Humidity: ${humidity.toStringAsFixed(1)} %
      Pressure: ${(pressure / 100).toStringAsFixed(2)} hPa
      """;
  }

  String _getImageForConditions(double temperature, double humidity) {
    // Determine temperature
    final bool isTempCold = temperature < 20;
    final bool isTempWarm = temperature >= 20 && temperature <= 25;
    final bool isTempHot = temperature > 25;

    // Determine humidity
    final bool isHumidityDry = humidity < 45;
    final bool isHumidityNormal = humidity >= 45 && humidity <= 55;
    final bool isHumidityWet = humidity > 55;

    // Both abnormal
    if (isTempCold && isHumidityDry) return 'images/coldDry.png';
    if (isTempCold && isHumidityWet) return 'images/coldWet.png';
    if (isTempHot && isHumidityDry) return 'images/hotDry.png';
    if (isTempHot && isHumidityWet) return 'images/hotWet.png';

    // Only temperature is abnormal
    if (isTempCold && isHumidityNormal) return 'images/cold.png';
    if (isTempHot && isHumidityNormal) return 'images/hot.png';

    // Only humidity is abnormal
    if (isTempWarm && isHumidityDry) return 'images/warmDry.png';
    if (isTempWarm && isHumidityWet) return 'images/warmWet.png';

    // Both are normal
    return 'images/warm.png';
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
            const SizedBox(height: 10),
            // IP Address input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ipController,
                    decoration: const InputDecoration(
                      labelText: 'Pico IP Address',
                      border: OutlineInputBorder(),
                      hintText: '192.168.1.45',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    // Hide keyboard
                    FocusScope.of(context).unfocus();
                    
                    setState(() {
                      picoIp = ipController.text;
                      isIpSet = true;
                    });
                    
                    // Start fetching and timers on first IP set
                    if (latestTimer == null && historyTimer == null) {
                      fetchEndpoint("latest");
                      fetchEndpoint("history");
                      
                      latestTimer = Timer.periodic(const Duration(seconds: 15), (_) {
                        fetchEndpoint("latest");
                      });
                      
                      historyTimer = Timer.periodic(const Duration(seconds: 60), (_) {
                        fetchEndpoint("history");
                      });
                    }
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('IP updated to: $picoIp')),
                    );
                  },
                  child: const Text('Set'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Latest section
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Image or loader
                    SizedBox(
                      width: 250,
                      height: 250,
                      child: 
                        !isIpSet ? 
                          const Text(
                              "Set the IP address first",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          :
                        currentImage.isNotEmpty
                          ? Image.asset(
                              currentImage,
                              width: 250,
                              height: 250,
                              fit: BoxFit.contain,
                            )
                          : 
                          const Center(
                              child: CircularProgressIndicator(),
                            ),
                    ),

                    const SizedBox(height: 10),

                    // Text aligned to image width
                    SizedBox(
                      width: 300,
                      child: Text(
                        latestText,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // History section
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
            const SizedBox(height: 100),
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
            child: loadingEndpoint == "clear_history" ? CircularProgressIndicator(strokeWidth: 2) : const Icon(Icons.delete),
          ),
        ],
      ),
    );
  }
}
