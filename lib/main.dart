import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:epubx/epubx.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
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

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _voiceSamplePath;

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

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _voiceSamplePath = path;
      });
    } else {
      if (await Permission.microphone.request().isGranted) {
        final dir = await getApplicationDocumentsDirectory();
        final filePath = '${dir.path}/my_voice_sample.wav';
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 24000),
          path: filePath,
        );
        setState(() {
          _isRecording = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step 1: Reference Voice Sample (15 sec)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _toggleRecording,
                          icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                          label: Text(_isRecording ? 'Stop Recording' : 'Record Voice'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _voiceSamplePath != null
                                ? 'Saved: my_voice_sample.wav'
                                : 'No sample recorded yet',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Book: $_bookTitle',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_chapterTitles.isNotEmpty) ...[
              DropdownButton<int>(
                isExpanded: true,
                value: _selectedChapter,
                items: List.generate(
                  _chapterTitles.length,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Text(
                      _chapterTitles[index],
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedChapter = val);
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    _chapters[_selectedChapter],
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                ),
              ),
            ] else
              const Expanded(
                child: Center(
                  child: Text('Tap the folder icon above to open an .epub book.'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
