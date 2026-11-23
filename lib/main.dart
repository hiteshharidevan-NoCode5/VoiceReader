import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:epubx/epubx.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Startup Error:\n${details.exception}',
            style: const TextStyle(color: Colors.red, fontSize: 14),
          ),
        ),
      ),
    );
  };
  runApp(const VoiceReaderApp());
}

class VoiceReaderApp extends StatelessWidget {
  const VoiceReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceReader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _bookTitle = 'No EPUB loaded';
  List<String> _chapters = [];
  List<String> _chapterTitles = [];
  int _selectedChapter = 0;

  AudioRecorder? _recorder;
  AudioPlayer? _samplePlayer;

  bool _isRecording = false;
  bool _isPaused = false;
  bool _isPlayingSample = false;
  String? _voiceSamplePath;
  String? _statusMessage;

  static const int _maxSeconds = 15;
  int _secondsLeft = _maxSeconds;
  Timer? _countdownTimer;

  static const String _sampleScript =
      '"Every morning before the city wakes up, I like to sit by the window '
      'with a warm cup of coffee and read a few pages of a good book. The quiet '
      'air makes it easy to focus on the rhythm of each sentence, whether the '
      'story is a fast-paced mystery or a thoughtful essay about history and science."';
  @override
  void initState() {
    super.initState();
    _initAudio();
    _checkExistingSample();
  }

  void _initAudio() {
    try {
      _recorder = AudioRecorder();
      _samplePlayer = AudioPlayer();
      _samplePlayer?.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _isPlayingSample = false);
        }
      });
    } catch (e) {
      setState(() => _statusMessage = 'Audio init warning: $e');
    }
  }

  Future<void> _checkExistingSample() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/my_voice_sample.wav');
      if (await file.exists()) {
        setState(() => _voiceSamplePath = file.path);
      }
    } catch (e) {
      setState(() => _statusMessage = 'Storage check warning: $e');
    }
  }

  String _formatTimer(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused) {
        if (_secondsLeft > 1) {
          setState(() => _secondsLeft--);
        } else {
          _stopRecording();
        }
      }
    });
  }

  Future<void> _startRecording() async {
    if (_isPlayingSample) {
      await _samplePlayer?.stop();
      setState(() => _isPlayingSample = false);
    }
    if (await Permission.microphone.request().isGranted) {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/my_voice_sample.wav';
      await _recorder?.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 24000),
        path: filePath,
      );
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _secondsLeft = _maxSeconds;
        _statusMessage = null;
      });
      _startTimer();
    }
  }

  Future<void> _togglePauseRecording() async {
    if (!_isRecording) return;
    if (_isPaused) {
      await _recorder?.resume();
      setState(() => _isPaused = false);
    } else {
      await _recorder?.pause();
      setState(() => _isPaused = true);
    }
  }

  Future<void> _stopRecording() async {
    _countdownTimer?.cancel();
    final path = await _recorder?.stop();
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _secondsLeft = _maxSeconds;
      _voiceSamplePath = path;
    });
  }

  Future<void> _togglePlaySample() async {
    if (_voiceSamplePath == null || _samplePlayer == null) return;
    if (_isPlayingSample) {
      await _samplePlayer!.stop();
      setState(() => _isPlayingSample = false);
    } else {
      await _samplePlayer!.setFilePath(_voiceSamplePath!);
      setState(() => _isPlayingSample = true);
      await _samplePlayer!.play();
    }
  }

  Future<void> _deleteSample() async {
    if (_isPlayingSample) {
      await _samplePlayer?.stop();
      setState(() => _isPlayingSample = false);
    }
    if (_voiceSamplePath != null) {
      final file = File(_voiceSamplePath!);
      if (await file.exists()) await file.delete();
    }
    setState(() {
      _voiceSamplePath = null;
      _secondsLeft = _maxSeconds;
    });
  }

  Future<void> _pickEpub() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      List<int> bytes = await file.readAsBytes();
      EpubBook epubBook = await EpubReader.readBook(bytes);
      List<String> titles = [];
      List<String> contents = [];
      if (epubBook.Chapters != null) {
        for (var chapter in epubBook.Chapters!) {
          String rawHtml = chapter.HtmlContent ?? '';
          String cleanText = rawHtml
              .replaceAll(RegExp(r'<[^>]*>'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (cleanText.isNotEmpty) {
            titles.add(chapter.Title ?? 'Chapter ${titles.length + 1}');
            contents.add(cleanText);
          }
        }
      }
      setState(() {
        _bookTitle = epubBook.Title ?? 'Untitled Book';
        _chapterTitles = titles;
        _chapters = contents;
        _selectedChapter = 0;
      });
    }
  }
  @override
  void dispose() {
    _countdownTimer?.cancel();
    _recorder?.dispose();
    _samplePlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoiceReader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open EPUB',
            onPressed: _pickEpub,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(_statusMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Step 1: Voice Sample',
                            style: Theme.of(context).textTheme.titleSmall),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isRecording
                                ? Colors.red.withValues(alpha: 0.15)
                                : Colors.grey.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Left: ${_formatTimer(_secondsLeft)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isRecording ? Colors.red : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        _sampleScript,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontStyle: FontStyle.italic,
                            height: 1.35),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!_isRecording)
                          ElevatedButton.icon(
                            onPressed: _startRecording,
                            icon: const Icon(Icons.mic),
                            label: Text(_voiceSamplePath == null
                                ? 'Record'
                                : 'Re-record'),
                          ),
                        if (_isRecording) ...[
                          OutlinedButton.icon(
                            onPressed: _togglePauseRecording,
                            icon: Icon(
                                _isPaused ? Icons.play_arrow : Icons.pause),
                            label: Text(_isPaused ? 'Resume' : 'Pause'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _stopRecording,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                          ),
                        ],
                        if (!_isRecording && _voiceSamplePath != null) ...[
                          OutlinedButton.icon(
                            onPressed: _togglePlaySample,
                            icon: Icon(_isPlayingSample
                                ? Icons.stop
                                : Icons.volume_up),
                            label: Text(
                                _isPlayingSample ? 'Stop' : 'Play Sample'),
                          ),
                          IconButton(
                            onPressed: _deleteSample,
                            tooltip: 'Delete Recording',
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Book: $_bookTitle',
                style: Theme.of(context).textTheme.titleMedium),
            if (_chapterTitles.isNotEmpty) ...[
              DropdownButton<int>(
                isExpanded: true,
                value: _selectedChapter,
                items: List.generate(
                  _chapterTitles.length,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Text(_chapterTitles[index],
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedChapter = val);
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(_chapters[_selectedChapter],
                      style: const TextStyle(fontSize: 16, height: 1.5)),
                ),
              ),
            ] else
              const Expanded(
                child: Center(
                  child:
                      Text('Tap the folder icon above to open an .epub book.'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
