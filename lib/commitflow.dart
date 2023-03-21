import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:args/args.dart';
import 'package:process_run/process_run.dart';

// Define the API key file path
final apiKeyFilePath = '.commitflow_api_key';

void main(List<String> arguments) async {
  // Check if git is installed
  await checkGitInstallation();

  final parser = ArgParser()
    ..addFlag('set_api_key', abbr: 's', help: 'Set a new OpenAI API key')
    ..addFlag('show_diff', abbr: 'd', help: 'Show the git diff output')
    ..addFlag('help',
        abbr: 'h', help: 'Display help information', negatable: false);

  final argsResults = parser.parse(arguments);

  if (argsResults['help']) {
    printUsage(parser);
  } else if (argsResults['set_api_key']) {
    await setApiKey();
  } else {
    String? apiKey = await getApiKey();

    if (apiKey == null) {
      print(
          'Error: No API key found. Please set an API key using the --set_api_key option.');
      exit(1);
    }

    String gitDiffOutput = await getGitDiff();

    if (argsResults['show_diff']) {
      print('Git diff output:\n$gitDiffOutput');
    }

    if (gitDiffOutput.trim().isEmpty) {
      print("No changes found. Don't forget to stage your changes!");
    } else {
      String commitMessage = await generateCommitMessage(gitDiffOutput, apiKey);
      print('Generated commit message: $commitMessage');
      await commitChanges(commitMessage);
    }
  }
}

Future<void> checkGitInstallation() async {
  try {
    final gitVersionResult = await Process.run('git', ['--version']);
    if (gitVersionResult.exitCode != 0 || gitVersionResult.stdout.isEmpty) {
      throw Exception('Git not found');
    }
  } catch (e) {
    print('Error: Git is not installed or not found in your system\'s PATH.');
    exit(1);
  }
}

void printUsage(ArgParser parser) {
  print('''
Usage: dart run bin/my_commitflow.dart [options]

Options:
${parser.usage}
''');
}

Future<void> setApiKey() async {
  stdout.write('Enter your OpenAI API key: ');
  String? apiKey = stdin.readLineSync();

  if (apiKey != null && apiKey.isNotEmpty) {
    await File(apiKeyFilePath).writeAsString(apiKey);
    print('API key saved successfully.');
  } else {
    print('Error: Invalid API key. Please try again.');
  }
}

Future<String?> getApiKey() async {
  try {
    String apiKey = await File(apiKeyFilePath).readAsString();
    return apiKey.trim();
  } catch (e) {
    return null;
  }
}

Future<String> getGitDiff() async {
  ProcessResult result =
      await runExecutableArguments('git', ['diff', '--cached']);

  return result.stdout;
}

Future<String> generateCommitMessage(String diff, String apiKey) async {
  final url = 'https://api.openai.com/v1/engines/text-davinci-003/completions';

  final response = await http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    },
    body: jsonEncode({
      'prompt': 'Generate a git commit message for this diff:\n$diff\n',
      'max_tokens': 50,
      'n': 3,
      'stop': null,
      'temperature': 0.7,
    }),
  );

  if (response.statusCode == 200) {
    Map<String, dynamic> jsonResponse = jsonDecode(response.body);
    List<dynamic> choices = jsonResponse['choices'];

    print('Generated commit messages:');
    for (int i = 0; i < choices.length; i++) {
      print('${i + 1}: ${choices[i]['text'].trim()}');
    }

    int? selectedIndex;
    do {
      stdout.write('Select a commit message (1-${choices.length}): ');
      selectedIndex = int.tryParse(stdin.readLineSync() ?? '-1');
    } while (selectedIndex == null ||
        selectedIndex < 1 ||
        selectedIndex > choices.length);

    String selectedCommitMessage = choices[selectedIndex - 1]['text'].trim();
    return selectedCommitMessage;
  } else {
    print(
        'Error: Failed to generate commit message. Status code: ${response.statusCode}');
    exit(1);
  }
}

Future<void> commitChanges(String commitMessage) async {
  ProcessResult result = await runExecutableArguments(
      'git', ['commit', '-a', '-m', commitMessage]);

  if (result.exitCode == 0) {
    print('Changes committed successfully.');
  } else {
    print('Error: Failed to commit changes.\n${result.stderr}');
  }
}
