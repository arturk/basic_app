import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
// ignore: depend_on_referenced_packages
import 'package:test_api/src/backend/invoker.dart';
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service.dart' as vm_service;
// ignore: depend_on_referenced_packages
import 'package:vm_service/vm_service_io.dart';

const basicTimeout = Duration(seconds: 10);
late String _dartVmServiceUrl;
late FlutterDriver _driver;

/// Class that encapsulates necessary android flutter driver connection params
class FlutterAndroidConnection {
  final String host;
  final String port;
  final String token;
  FlutterAndroidConnection(this.host, this.port, this.token);
}

/// Function for getting the latest android flutter driver connection
FlutterAndroidConnection _getFlutterAndroidVMSConnection() {
  final process = Process.runSync('adb', ['logcat', '-d'],
      stdoutEncoding: const AsciiCodec(allowInvalid: true));
  var observatoryUri = process.stdout
      .toString()
      .split('\n')
      .lastWhere((line) => line.contains('Dart VM'))
      .split('http://')
      .last;
  observatoryUri = observatoryUri.substring(0, observatoryUri.length - 2);
  final host = observatoryUri.split(':').first;
  final token = '${observatoryUri.split('/').last}=';
  final port = observatoryUri.split(':').last.split('/').first;
  Process.runSync('adb', ['forward', 'tcp:$port', 'tcp:$port']);
  return FlutterAndroidConnection(host, port, token);
}

void _resetPortForwarding() =>
    Process.runSync('adb', ['forward', '--remove-all']);

Future<FlutterDriver> initAndroidFlutterDriver() async {
  final connection = _getFlutterAndroidVMSConnection();
  _dartVmServiceUrl =
      'ws://${connection.host}:${connection.port}/${connection.token}/ws';
  _driver = await FlutterDriver.connect(
      dartVmServiceUrl: _dartVmServiceUrl,
      printCommunication: true,
      timeout: basicTimeout);
  Invoker.current!.addTearDown(_writeCoverageData);
  await _driver.startTracing(streams: [TimelineStream.all]);
  _driver.serviceClient.setFlag("profiler", "true");
  return _driver;
}

Future _writeCoverageData() async {
  vm_service.VmService vms = await vmServiceConnectUri(_dartVmServiceUrl);
  String isolateId = _driver.appIsolate.id!;
  final pjson = (await vms.getSourceReport(
    isolateId,
    [vm_service.SourceReportKind.kCoverage],
    reportLines: true,
  ))
      .json!;

  var finalJson = []; // final json to be recorded as source report
  for (var range in pjson['ranges']) {
    if (range['compiled'] == true) {
      // we are interested only in our files and only those that had executed code
      range['scriptUri'] =
          pjson['scripts'][range['scriptIndex']]['uri']; // add path to file
      if (!range['scriptUri'].contains('basic_app')) {
        continue;
      }
      finalJson.add(range);
    }
  }
  File("$testOutputsDirectory/source_coverage.json").writeAsStringSync(
    jsonEncode(finalJson),
  );
  await _driver.close();
  _resetPortForwarding();
  writeMainFileReportCoverage(finalJson);
}

void writeMainFileReportCoverage(List<dynamic> jsonList) {
  const spanHtmlExecStart = '<span style="background-color:#00FF00">';
  const spanHtmlNotExecStart = '<span style="background-color:#FF0000">';
  var sourceLines =
      File("$testOutputsDirectory/../lib/main.dart").readAsLinesSync();
  var executedLines = [];
  var nonExecutedLines = [];
  for (var rec in jsonList) {
    executedLines.addAll(rec['coverage']['hits']);
    nonExecutedLines.addAll(rec['coverage']['misses']);
  }
  var htmlBody = '<html><body>';
  for (var i = 0; i < sourceLines.length; i++) {
    if (nonExecutedLines.contains(i+1)) {
      htmlBody += spanHtmlNotExecStart + sourceLines[i] + '</span>';
    } else if (executedLines.contains(i+1)) {
      htmlBody += spanHtmlExecStart + sourceLines[i] + '</span>';
    } else {
      htmlBody += sourceLines[i];
    }
    htmlBody += '<br />';
  }
  htmlBody += '</body></html>';
  File("$testOutputsDirectory/source_coverage.html").writeAsStringSync(
    htmlBody,
  );
}
