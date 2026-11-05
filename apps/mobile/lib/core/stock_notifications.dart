import 'package:flutter/services.dart';

class StockNotifications {
  static const channel = MethodChannel('uz.savdoyordam/notifications');
  static Future<bool> request() async =>
      await channel.invokeMethod<bool>('request') ?? false;
  static Future<String?> pushToken() async =>
      channel.invokeMethod<String>('pushToken');
  static Future<void> show(String title, String body) async =>
      channel.invokeMethod<void>('show', {'title': title, 'body': body});
  static Future<void> clear() async => channel.invokeMethod<void>('clear');
  static Future<void> cancel() async => channel.invokeMethod<void>('cancel');
}
