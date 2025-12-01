import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';

import 'package:flutter_app/main.dart'; 
import 'mocks.mocks.dart';

void main() {
  group("PicoApp HTTP tests", () {
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient();
    });

    testWidgets("Fetch latest – success", (WidgetTester tester) async {
      // Mock response
      when(mockClient.get(any))
          .thenAnswer((_) async => http.Response("1700000000,100.5,23.1,41.2", 200));

      await tester.pumpWidget(MaterialApp(
        home: PicoHomePage(client: mockClient),
      ));

      // Press "latest"
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump(); // start loading
      await tester.pump(const Duration(milliseconds: 100)); // finish async

      expect(find.textContaining("Time:"), findsOneWidget);
      expect(find.textContaining("Pressure: 100.50 Pa"), findsOneWidget);
      expect(find.textContaining("Temperature: 23.1 °C"), findsOneWidget);
    });

    testWidgets("Fetch history – success", (tester) async {
      when(mockClient.get(any))
          .thenAnswer((_) async => http.Response("item1\nitem2", 200));

      await tester.pumpWidget(MaterialApp(
        home: PicoHomePage(client: mockClient),
      ));

      await tester.tap(find.byIcon(Icons.list));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining("History Results:"), findsOneWidget);
      expect(find.textContaining("item1"), findsOneWidget);
    });

    testWidgets("Clear history – success", (tester) async {
      when(mockClient.get(any))
          .thenAnswer((_) async => http.Response("OK", 200));

      await tester.pumpWidget(MaterialApp(
        home: PicoHomePage(client: mockClient),
      ));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text("History cleared successfully."), findsOneWidget);
    });

    testWidgets("HTTP error test (404)", (tester) async {
      when(mockClient.get(any))
          .thenAnswer((_) async => http.Response("Not found", 404));

      await tester.pumpWidget(MaterialApp(
        home: PicoHomePage(client: mockClient),
      ));

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining("Latest Error: HTTP 404"), findsOneWidget);
    });
  });
}