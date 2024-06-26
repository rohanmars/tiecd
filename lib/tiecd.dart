import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'api/types.dart';
import 'src/core/build.dart';
import 'src/core/deploy.dart';
import 'src/log.dart';
import 'src/util/options_printer.dart';

Map<String, String> envVars = Platform.environment;

String setupStringValue(String? newValue, String? envName) {
  return setupStringValueWithDefault('', newValue, envName);
}

String setupStringValueWithDefault(
    String? defaultValue, String? newValue, String? envName) {
  if (newValue != null) {
    if (newValue.startsWith('=')) {
      newValue = newValue.substring(1);
    }
  }
  if (envName != null) {
    if (envVars[envName] != null) {
      return envVars[envName]!;
    } else if (envVars['INPUT_$envName'] != null) {
      // github actions
      return envVars['INPUT_$envName']!;
    }
  }
  if (newValue != null) {
    return newValue;
  } else if (defaultValue != null) {
    return defaultValue;
  } else {
    return '';
  }
}

bool setupBoolValue(bool value, String? envName) {
  bool? envResult;
  if (envName != null) {
    if (envVars[envName] != null) {
      envResult = bool.tryParse(envVars[envName]!, caseSensitive: false);
    } else if (envVars['INPUT_$envName'] != null) {
      // github actions
      envResult =
          bool.tryParse(envVars['INPUT_$envName']!, caseSensitive: false);
    }
  }
  if (envResult != null) {
    return envResult;
  } else {
    return value;
  }
}

Future<void> processGitLog(Config config) async {
  // is this a git repository?
  if (File('.git/config').existsSync()) {
    // set safe directory to workspace for github runners
    if (envVars['GITHUB_WORKSPACE'] != null) {
      await Process.run('ls', [
        'config',
        '--global',
        'safe.directory',
        envVars['GITHUB_WORKSPACE']!
      ]);
    }

    // check the the HEAD commit message for steps/files overrides
    var buffer = await Process.run('git', ['log', '-1', '--pretty=%B']);
    var lines = buffer.stdout.split('/\r?\n/');

    // process files
    if (config.files == '') {
      var files = config.filesCommitPrefix.split('|');
      var regex = '';
      for (var file in files) {
        regex += '$file=|';
      }
      regex = regex.substring(0, regex.length - 1);
      RegExp separator = RegExp(regex);

      for (var line in lines) {
        var parts = line.replaceAll('\n', '').split(separator);
        if (parts.length == 2) {
          if (parts[1].contains(' ')) {
            config.files = parts[1]
                .substring(0, parts[1].indexOf(' '))
                .replaceAll('\n', '');
          } else {
            config.files = parts[1].replaceAll('\n', '');
          }
          break; // ignore other lines
        } else if (parts.length > 2) {
          throw TieError('more then one files= option is specified in commit message');
        }
      }
    }

    // process app
    if (config.apps == '') {
      var steps = config.appsCommitPrefix.split('|');
      var regex = '';
      for (var step in steps) {
        regex += '$step=|';
      }
      regex = regex.substring(0, regex.length - 1);
      RegExp separator = RegExp(regex);

      for (var line in lines) {
        var parts = line.split(separator);
        if (parts.length == 2) {
          // only take value up to first space
          if (parts[1].contains(' ')) {
            config.apps = parts[1]
                .substring(0, parts[1].indexOf(' '))
                .replaceAll('\n', '');
          } else {
            config.apps = parts[1].replaceAll('\n', '');
          }
          break; // ignore other lines
        } else if (parts.length > 2) {
          throw TieError('more then one apps= option is specified in commit message');
        }
      }
    }
  }
}

void showHeader(Config config) {
  if (config.banner) {
    print(' ');
    print('  ████████╗ ██╗ ███████╗  ██████╗ ██████╗ ');
    print('  ╚══██╔══╝ ╚═╝ ██╔════╝ ██╔════╝ ██╔══██╗');
    print('     ██║    ██╗ █████╗   ██║      ██║  ██║');
    print('     ██║    ██║ ██╔══╝   ██║      ██║  ██║');
    print('     ██║    ██║ ███████╗ ╚██████╗ ██████╔╝');
    print('     ╚═╝    ╚═╝ ╚══════╝  ╚═════╝ ╚═════╝ ');
    print(' ');
    print('             https://tie.cd');
    print(' ');
  }
  if (config.verbose) {
    Log.info(' --- Runtime Configuration ---');
    OptionsPrinter printer = OptionsPrinter();
    printer.add('base-dir', config.baseDir);
    printer.add('target', config.target);
    printer.add('files', config.files);
    printer.add('files-commit-prefix', config.filesCommitPrefix);
    printer.add('apps', config.apps);
    printer.add('apps-commit-prefix', config.appsCommitPrefix);
    printer.add('file-prefix', config.filePrefix);
    printer.add('secret-labels', config.secretLabels);
    printer.add('app-names-required', config.appNamesRequired.toString());
    printer.add('ignore-errors', config.ignoreErrors.toString());
    printer.add('verbose', config.verbose.toString());
    printer.add('trace-generated', config.traceGenerated.toString());
    printer.add('trace-tie-file', config.traceTieFile.toString());
    printer.add('trace-commands', config.traceCommands.toString());
    printer.add('banner', config.banner.toString());
    printer.add('create-namespaces', config.createNamespaces.toString());
    printer.add('auto-generated-cleanup', config.autoGeneratedCleanup.toString());
    printer.add('auto-generated-cleanup-dry-run',config.autoGeneratedCleanupDryRun.toString());
    printer.print();
    Log.info(' ---');
  }
}

Future<Config> buildConfig(final ArgResults argResults) async {
  Config config = Config();

  // process args then override with environment variable values
  config.filesCommitPrefix = setupStringValue(
      argResults['files-commit-prefix'], 'TIECD_FILES_COMMIT_PREFIX');
  config.appsCommitPrefix = setupStringValue(
      argResults['apps-commit-prefix'], 'TIECD_APPS_COMMIT_PREFIX');

  // process git log
  await processGitLog(config);

  // now process reset of the configuration with higher precedence
  config.baseDir = setupStringValue(argResults['base-dir'], 'TIECD_BASE_DIR');
  config.target = setupStringValue(argResults['target'], 'TIECD_TARGET');
  config.files = setupStringValueWithDefault(
      config.files, argResults['files'], 'TIECD_FILES');
  config.apps = setupStringValueWithDefault(
      config.apps, argResults['apps'], 'TIECD_APPS');
  config.filePrefix =
      setupStringValue(argResults['file-prefix'], 'TIECD_FILE_PREFIX');
  config.appNamesRequired = setupBoolValue(
      argResults['app-names-required'], 'TIECD_APP_NAMES_REQUIRED');
  config.ignoreErrors =
      setupBoolValue(argResults['ignore-errors'], 'TIECD_IGNORE_ERRORS');
  config.verbose = setupBoolValue(argResults['verbose'], 'TIECD_VERBOSE');
  if (config.verbose) {
    config.traceTieFile = true;
    config.traceCommands = true;
    config.traceGenerated = true;
  }
  if (argResults.wasParsed('trace-generated')) {
    config.traceGenerated = setupBoolValue(argResults['trace-generated'], 'TIECD_TRACE_GENERATED');
  }
  if (argResults.wasParsed('trace-tie-file')) {
    config.traceTieFile = setupBoolValue(argResults['trace-tie-file'], 'TIECD_TRACE_TIE_FILE');
  }
  if (argResults.wasParsed('trace-commands')) {
    config.traceCommands = setupBoolValue(argResults['trace-commands'], 'TIECD_TRACE_COMMANDS');
  }
  config.secretLabels =
      setupStringValue(argResults['secret-labels'], 'TIECD_SECRET_LABELS');
  config.banner = setupBoolValue(argResults['banner'], 'TIECD_BANNER');
  config.createNamespaces = setupBoolValue(
      argResults['create-namespaces'], 'TIECD_CREATE_NAMESPACES');
  config.autoGeneratedCleanup = setupBoolValue(
      argResults['auto-generated-cleanup'], 'TIECD_AUTO_GENERATED_CLEANUP');
  config.autoGeneratedCleanupDryRun = setupBoolValue(
      argResults['auto-generated-cleanup-dry-run'], 'TIECD_AUTO_GENERATED_CLEANUP_DRY_RUN');

  // post config init
  var secretLabels = config.secretLabels.split('|');
  for (var label in secretLabels) {
    config.secretLabelSet.add(label.toLowerCase());
  }

  showHeader(config);

  // additional option checking
  if (config.appNamesRequired && config.apps == '') {
    throw TieError('apps names required option is set but no app names have been set');
  }
  if (config.apps == 'all') {
    config.apps = '';
  }

  return config;
}

class DeployCommand extends Command {
  @override
  final name = 'deploy';
  @override
  final description = 'Deploy process on current directory';

  @override
  Future<void> run() async {
    var config = await buildConfig(globalResults!);
    DeployExecutor deploy = DeployExecutor(config);
    await deploy.run();
  }
}

class BuildCommand extends Command {
  @override
  final String name = 'build';
  @override
  final String description = 'Build project from source code';

  @override
  Future<void> run() async {
    var config = await buildConfig(globalResults!);
    BuildExecutor build = BuildExecutor(config);
    await build.run();
  }
}

Future<void> main(List<String> arguments) async {
  var runner = CommandRunner('tiecd',
      'Pipeline tools for cloud deployments');

  runner.argParser.addOption('base-dir',
      abbr: 'b',
      help:
      'Directory containing tie.yml and deployment files [env: TIECD_BASE_DIR]');
  runner.argParser.addOption('target',
      abbr: 't',
      help:
      'Sub action to run [env: TIECD_TARGET]');
  runner.argParser.addOption('files',
      abbr: 'f', help: 'Specific files to run [env: TIECD_FILES]');
  runner.argParser.addOption('files-commit-prefix',
      defaultsTo: 'file|files',
      help:
      'String prefixes to search for in commit message to specify files to process, i.e. file=tieapp.yaml [env: TIECD_FILES_COMMIT_PREFIX]');
  runner.argParser.addOption('apps',
      abbr: 'a', help: 'Override which apps to run [env: TIECD_APPS]');
  runner.argParser.addOption('apps-commit-prefix',
      defaultsTo: 'app|apps|run|update',
      help:
      'String prefixes to search for commit message to specify apps to process, i.e. apps=myapp [env: TIECD_APPS_COMMIT_PREFIX]');
  runner.argParser.addOption('file-prefix',
      abbr: 'p',
      defaultsTo: 'tie',
      help:
      'File prefix for tie.yml files, defaults to tie [env: TIECD_FILE_PREFIX]');
  runner.argParser.addFlag('app-names-required',
      abbr: 'r',
      defaultsTo: false,
      negatable: false,
      help:
      'Only execute the app names that are passed at runtime [env: TIECD_APP_NAMES_REQUIRED]');
  runner.argParser.addFlag('ignore-errors',
      defaultsTo: false,
      negatable: false,
      help:
      'Ignore errors keep processing other apps [env: TIECD_IGNORE_ERRORS]');
  runner.argParser.addFlag('verbose',
      abbr: 'v',
      defaultsTo: false,
      negatable: false,
      help:
      'Increase logging to include all tracing and additional informational logging');
  runner.argParser.addFlag('trace-generated',
      help: 'Log generated artifacts [env: TIECD_TRACE_GENERATED]');
  runner.argParser.addFlag('trace-tie-file',
      help: 'Log generated and expanded tie files [env: TIECD_TRACE_TIE_FILE]');
  runner.argParser.addFlag('trace-commands',
      help: 'Log executed commands [env: TIECD_TRACE_COMMANDS]');
  runner.argParser.addOption('secret-labels',
      defaultsTo: 'pass|secret|token|key|cert',
      help:
      'Labels used to indicate secret values which will be redacted form console output [env: TIECD_SECRET_LABELS]');
  runner.argParser.addFlag('banner',
      defaultsTo: true,
      help: 'Show TIECD banner header during execution [env: TIECD_BANNER]');
  runner.argParser.addFlag('create-namespaces',
      defaultsTo: true,
      help:
      'Auto create namespaces if necessary [env: TIECD_CREATE_NAMESPACES]');
  runner.argParser.addFlag('auto-generated-cleanup',
      defaultsTo: false,
      help:
      'Cleanup auto generated resources during deployment [env: TIECD_AUTO_GENERATED_CLEANUP]');
  runner.argParser.addFlag('auto-generated-cleanup-dry-run',
      defaultsTo: false,
      help:
      'Dry run of cleanup of auto generated resources during deployment [env: TIECD_AUTO_GENERATED_CLEANUP_DRY_RUN]');

  runner..addCommand(DeployCommand())..addCommand(BuildCommand());
  try {
    await runner.run(arguments);
  } on TieError catch (error) {
    Log.error(error.cause);
    rethrow;
  }
}
