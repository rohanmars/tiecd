import 'dart:io';

import 'package:meta/meta.dart';

import '../../api/tiefile.dart';
import '../../api/types.dart';
import '../log.dart';
import '../util.dart';
import '../extensions.dart';
import 'kubernetes_handler.dart';

class OKDHandler extends KubernetesHandler {
  OKDHandler(super.config);

  @override
  Future<void> expandEnvironment(Environment environment) async {
    await super.expandEnvironment(environment);
  }

  @override
  Future<void> login(Environment environment) async {
    var environmentName = environment.name;
    environmentName ??= '';

    if (environment.apiUrl.isNullOrEmpty) {
      throw TieError("cluster $environmentName apiUrl is not set");
    }

    // OKD-specific authentication using oc login
    if (environment.apiToken.isNotNullNorEmpty) {
      Log.info('logging into OKD cluster using token authentication');
      await _ocLogin(environment);
    } else if (environment.apiClientCert.isNotNullNorEmpty &&
        environment.apiClientKey.isNotNullNorEmpty) {
      Log.info('logging into OKD cluster using client certificate authentication');
      await _ocLogin(environment);
    } else {
      throw TieError(
          "cluster $environmentName apiToken or apiClientCert/apiClientKey is not set");
    }

    // Call parent login for additional setup
    await super.login(environment);
  }

  Future<void> _ocLogin(Environment environment) async {
    var args = <String>[];
    args.add('login');
    args.add(environment.apiUrl!);

    // Add authentication method
    if (environment.apiToken.isNotNullNorEmpty) {
      args.add('--token');
      args.add(environment.apiToken!);
    }

    // Handle TLS verification
    if (environment.apiTlsVerify == false) {
      args.add('--insecure-skip-tls-verify');
    }

    // Set kubeconfig file location
    if (kubeConfigFilename != null) {
      args.add('--kubeconfig');
      args.add(kubeConfigFilename!);
    }

    // Run oc login command
    var result = await Process.run('oc', args, 
        environment: getHandlerEnv(), 
        runInShell: true);

    if (result.exitCode != 0) {
      var errorOutput = result.stderr ?? result.stdout;
      throw TieError("OKD login failed: $errorOutput");
    }

    Log.info('OKD login successful');
  }

  @override
  Map<String, String> getHandlerEnv() {
    Map<String, String> env = super.getHandlerEnv();
    // OKD handlers may need additional environment variables
    return env;
  }

  @override
  Future<void> logoff() async {
    try {
      // Attempt to logout from OKD
      var result = await Process.run('oc', ['logout'], 
          environment: getHandlerEnv(), 
          runInShell: true);
      
      if (result.exitCode == 0) {
        Log.info('OKD logout successful');
      }
    } catch (error) {
      Log.error('Error during OKD logout: $error');
    }

    // Call parent logoff for cleanup
    await super.logoff();
  }
}